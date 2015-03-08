package MediaWords::StoryVectors;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# methods to generate the story_sentences and story_sentence_words and associated aggregated tables

use strict;
use warnings;

use Data::Dumper;

use MediaWords::Languages::Language;
use MediaWords::DBI::Stories;
use MediaWords::Util::Countries;
use MediaWords::Util::HTML;
use MediaWords::Util::IdentifyLanguage;
use MediaWords::Util::SQL;
use MediaWords::Util::CoreNLP;

use Date::Format;
use Date::Parse;
use Digest::MD5;
use Encode;
use utf8;
use Readonly;
use Text::CSV_XS;

# minimum length of words in story_sentence_words
use constant MIN_STEM_LENGTH => 3;

Readonly my $sentence_study_table_prefix => 'sen_study_old_';
Readonly my $sentence_study_table_suffix => '_2011_01_03_2011_01_10';

# if story is a ref, return itself, otherwise treat it as a stories_id and query for the story ref
sub _get_story
{
    my ( $db, $story ) = @_;

    if ( ref( $story ) )
    {
        return $story;
    }
    else
    {
        return $db->query(
            <<"EOF",
            SELECT stories_id,
                   publish_date,
                   media_id,
                   url
            FROM stories
            WHERE stories_id = ?
EOF
            $story
        )->hash;
    }
}

# given a hash of word counts by sentence, insert the words into the db
sub _insert_story_sentence_words
{
    my ( $db, $story, $word_counts ) = @_;

    my $copy = <<END;
copy story_sentence_words (stories_id, stem_count, sentence_number, stem, term, publish_day, media_id) from STDIN
END
    eval { $db->dbh->do( $copy ) };
    if ( $@ )
    {
        die( " Error on copy for story_sentence_words: $@" );
    }

    while ( my ( $sentence_num, $sentence_counts ) = each( %{ $word_counts } ) )
    {
        while ( my ( $stem, $hash ) = each( %{ $sentence_counts } ) )
        {
            my $data = join( "\t",
                $story->{ stories_id },
                $hash->{ count },
                $sentence_num,
                encode_utf8( $stem ),
                encode_utf8( lc( $hash->{ word } ) ),
                $story->{ publish_date },
                $story->{ media_id } );

            eval { $db->dbh->pg_putcopydata( "$data\n" ); };

            if ( $@ )
            {
                die( " Error on pg_putcopydata for story_sentence_words: $@" );
            }
        }
    }

    eval { $db->dbh->pg_putcopyend(); };

    if ( $@ )
    {
        die( " Error on pg_putcopyend for story_sentence_words: $@" );
    }
}

# return 1 if the stem passes various tests
sub _valid_stem
{
    my ( $stem, $word, $stop_stems ) = @_;

    return ( $stem
          && ( length( $stem ) >= MIN_STEM_LENGTH )
          && ( !$stop_stems->{ $stem } )
          && ( $word !~ /[^[:print:]]/ )
          && ( $word =~ /[^[:digit:][:punct:]]/ ) );
}

# insert the story sentences into the db
sub _insert_story_sentences
{
    my ( $db, $story, $sentences ) = @_;

    my $fields = [ qw/stories_id sentence_number sentence language publish_date media_id/ ];
    my $field_list = join( ',', @{ $fields } );

    my $copy = <<END;
copy story_sentences ( $field_list ) from STDIN with csv
END
    eval { $db->dbh->do( $copy ) };
    die( " Error on copy for story_sentences: $@" ) if ( $@ );

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    for my $sentence ( @{ $sentences } )
    {
        $csv->combine( map { $sentence->{ $_ } } @{ $fields } );
        eval { $db->dbh->pg_putcopydata( $csv->string . "\n" ) };

        die( " Error on pg_putcopydata for story_sentences: $@" ) if ( $@ );
    }

    eval { $db->dbh->pg_putcopyend() };

    die( " Error on pg_putcopyend for story_sentences: $@" ) if ( $@ );
}

# if the length of the string is greater than the given length, cut to that length
sub limit_string_length
{

    # my ( $s, $l ) = @_;

    if ( length( $_[ 0 ] ) > $_[ 1 ] )
    {
        substr( $_[ 0 ], $_[ 1 ] ) = '';
    }
}

# efficient copy insertion of story sentence counts
sub insert_story_sentence_counts
{
    my ( $db, $story, $md5s ) = @_;

    my $fields = [ qw/sentence_md5 media_id publish_week first_stories_id first_sentence_number sentence_count/ ];
    my $field_list = join( ',', @{ $fields } );

    my ( $publish_week ) = $db->query( "select date_trunc( 'week', ?::date )", $story->{ publish_date } )->flat;

    my $copy = <<END;
copy story_sentence_counts ( $field_list ) from STDIN with csv
END
    eval { $db->dbh->do( $copy ) };
    die( "Error on copy for story_sentence_counts: $@" ) if ( $@ );

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    my $i = 0;
    for my $md5 ( @{ $md5s } )
    {
        $csv->combine( $md5, $story->{ media_id }, $publish_week, $story->{ stories_id }, $i++, 1 );
        eval { $db->dbh->pg_putcopydata( $csv->string . "\n" ) };

        die( "Error on pg_putcopydata for story_sentence_counts: $@" ) if ( $@ );
    }

    eval { $db->dbh->pg_putcopyend() };

    die( "Error on pg_putcopyend for story_sentence_counts: $@" ) if ( $@ );
}

# return the sentences from the set that are dups within the same media source and calendar week.
# also adds the sentence to the story_sentences_count table and/or increments the count in that table
# for the sentence.
#
# NOTE: you must wrap a 'lock story_sentence_counts in row exclusive mode' around all calls to this within the
# same transaction to avoid deadlocks
#
# NOTE ALSO: There is a known concurrency issue if this function is called by multiple threads see #1599
# However, we have determined that the issue is rare enough in practice that it is not of particular concern.
# So we have decided to simply leave things in place as they are rather than risk the performance and code complexity issues
# of ensuring atomic updates.
#
sub get_deduped_sentences
{
    my ( $db, $story, $sentences ) = @_;

    my $sentence_md5_lookup = {};
    my $i                   = 0;
    for my $sentence ( @{ $sentences } )
    {
        my $sentence_utf8 = encode_utf8( $sentence );
        unless ( defined $sentence_utf8 )
        {
            die "Sentence '$sentence' for story " . $story->{ stories_id } . " is undefined after encoding it to UTF-8.";
        }

        my $sentence_utf8_md5 = Digest::MD5::md5_hex( $sentence_utf8 );
        unless ( $sentence_utf8_md5 )
        {
            die "Sentence's '$sentence' MD5 hash is empty or undef.";
        }

        my $sentence_data = {
            md5      => $sentence_utf8_md5,
            sentence => $sentence,
            num      => $i++
        };
        $sentence_md5_lookup->{ $sentence_utf8_md5 } = $sentence_data;
    }

    my $sentence_md5_list = join( ',', map { "'$_'" } keys %{ $sentence_md5_lookup } );

    my $sentence_dup_info = $db->query(
        <<"END",
        SELECT MIN( story_sentence_counts_id) AS story_sentence_counts_id,
               sentence_md5
        FROM story_sentence_counts
        WHERE sentence_md5 IN ( $sentence_md5_list )
          AND media_id = ?
          AND publish_week = DATE_TRUNC( 'week', ?::date )
        GROUP BY story_sentence_counts_id
END
        $story->{ media_id }, $story->{ publish_date }
    )->hashes;

    my $story_sentence_counts_ids = [];
    for my $sdi ( @{ $sentence_dup_info } )
    {
        push( @{ $story_sentence_counts_ids }, $sdi->{ story_sentence_counts_id } );
        delete( $sentence_md5_lookup->{ $sdi->{ sentence_md5 } } );
    }

    my $deduped_sentence_data = [ sort { $a->{ num } <=> $b->{ num } } values( %{ $sentence_md5_lookup } ) ];
    my $deduped_md5s          = [ map  { $_->{ md5 } } @{ $deduped_sentence_data } ];
    my $deduped_sentences     = [ map  { $_->{ sentence } } @{ $deduped_sentence_data } ];

    if ( @{ $story_sentence_counts_ids } )
    {
        my $id_list = join( ',', @{ $story_sentence_counts_ids } );
        $db->query(
            <<"END"
            UPDATE story_sentence_counts
            SET sentence_count = sentence_count + 1
            WHERE story_sentence_counts_id IN ( $id_list )
END
        );
    }

    insert_story_sentence_counts( $db, $story, $deduped_md5s );

    return $deduped_sentences;
}

# given a story and a list of sentences, return all of the stories that are not duplicates as defined by
# count_duplicate_sentences()
sub dedup_sentences
{
    my ( $db, $story, $sentences ) = @_;

    unless ( $sentences and @{ $sentences } )
    {
        warn "Sentences for story " . $story->{ stories_id } . " is undef or empty.";
        return [];
    }

    if ( !$db->dbh->{ AutoCommit } )
    {
        $db->query( "LOCK TABLE story_sentence_counts IN ROW EXCLUSIVE MODE" );
    }

    my $deduped_sentences = get_deduped_sentences( $db, $story, $sentences );

    $db->dbh->{ AutoCommit } || $db->commit;

    if ( @{ $sentences } && !@{ $deduped_sentences } )
    {
        # FIXME - should do something here to find out if this is just a duplicate story and
        # try to merge the given story with the existing one
        print STDERR "all sentences deduped for stories_id $story->{ stories_id }\n";
    }

    return $deduped_sentences;
}

sub get_default_story_words_start_date
{
    my $default_story_words_start_date =
      MediaWords::Util::Config::get_config->{ mediawords }->{ default_story_words_start_date };

    return $default_story_words_start_date;
}

sub get_default_story_words_end_date
{
    my $default_story_words_end_date =
      MediaWords::Util::Config::get_config->{ mediawords }->{ default_story_words_end_date };

    return $default_story_words_end_date;
}

sub _medium_has_story_words_start_date
{
    my ( $medium ) = @_;

    my $default_story_words_start_date = get_default_story_words_start_date();

    return defined( $default_story_words_start_date ) || $medium->{ sw_data_start_date };
}

sub _get_story_words_start_date_for_medium
{
    my ( $medium ) = @_;

    if ( defined( $medium->{ sw_data_start_date } ) && $medium->{ sw_data_start_date } )
    {
        return $medium->{ sw_data_start_date };
    }

    my $default_story_words_start_date = get_default_story_words_start_date();

    return $default_story_words_start_date;
}

sub _medium_has_story_words_end_date
{
    my ( $medium ) = @_;

    my $default_story_words_end_date = get_default_story_words_end_date();

    return defined( $default_story_words_end_date ) || $medium->{ sw_data_end_date };
}

sub _get_story_words_end_date_for_medium
{

    my ( $medium ) = @_;

    if ( defined( $medium->{ sw_data_end_date } ) && $medium->{ sw_data_end_date } )
    {
        return $medium->{ sw_data_end_date };
    }
    else
    {
        my $default_story_words_end_date = get_default_story_words_end_date();

        return $default_story_words_end_date;
    }

}

sub _date_within_media_source_story_words_range
{
    my ( $medium, $publish_date ) = @_;

    if ( _medium_has_story_words_start_date( $medium ) )
    {
        my $medium_sw_start_date = _get_story_words_start_date_for_medium( $medium );

        return 0 if $medium_sw_start_date gt $publish_date;
    }

    if ( _medium_has_story_words_end_date( $medium ) )
    {
        my $medium_sw_end_date = _get_story_words_end_date_for_medium( $medium );

        return 0 if $medium_sw_end_date lt $publish_date;
    }

    return 1;
}

sub _story_within_media_source_story_words_date_range
{
    my ( $db, $story ) = @_;

    my $medium = MediaWords::DBI::Stories::get_media_source_for_story( $db, $story );

    my $publish_date = $story->{ publish_date };

    return _date_within_media_source_story_words_range( $medium, $publish_date );

    return 1;
}

sub purge_story_words_data_for_unretained_dates
{
    my ( $db ) = @_;

    my $default_story_words_start_date = get_default_story_words_start_date();
    my $default_story_words_end_date   = get_default_story_words_end_date();

    $db->query( " SELECT purge_story_words( ? , ? )", $default_story_words_start_date, $default_story_words_end_date );

    return;
}

sub purge_story_sentences_data_for_unretained_dates
{
    my ( $db ) = @_;

    my $default_story_words_start_date = get_default_story_words_start_date();
    my $default_story_words_end_date   = get_default_story_words_end_date();

    $db->query(
        " SELECT purge_story_sentences( ?::date , ?::date )",
        $default_story_words_start_date,
        $default_story_words_end_date
    );

    return;
}

sub purge_story_sentence_counts_data_for_unretained_dates
{
    my ( $db ) = @_;

    my $default_story_words_start_date = get_default_story_words_start_date();
    my $default_story_words_end_date   = get_default_story_words_end_date();

    $db->query(
        " SELECT purge_story_sentence_counts( ?::date , ?::date )",
        $default_story_words_start_date,
        $default_story_words_end_date
    );

    return;
}

sub purge_daily_words_data_for_unretained_dates
{
    my ( $db ) = @_;

    my $default_story_words_start_date = get_default_story_words_start_date();
    my $default_story_words_end_date   = get_default_story_words_end_date();

    $db->query(
        <<"EOF",
        SELECT purge_daily_words_for_media_set( media_sets_id, ?::date, ?::date)
        FROM media_sets
        ORDER BY media_sets_id
EOF
        $default_story_words_start_date,
        $default_story_words_end_date
    );

    return;
}

sub _get_sentences_from_story_text
{
    my ( $story_text, $story_lang ) = @_;

    # Tokenize into sentences
    my $lang = MediaWords::Languages::Language::language_for_code( $story_lang );
    if ( !$lang )
    {
        $lang = MediaWords::Languages::Language::default_language();
    }

    my $sentences = $lang->get_sentences( $story_text );

    return $sentences;
}

# apply manual filters to clean out sentences that we think are junk. edits the $sentences array in place with splice
sub clean_sentences
{
    my ( $sentences ) = @_;

    # first walk through the array, then prune any sentences we want to drop; this approach allows to splice in place
    my $prune_indices = [];
    for ( my $i = 0; $i < @{ $sentences }; $i++ )
    {
        push( @{ $prune_indicies }, $i ) if ( $sentence->[ $i ] =~ /(\[.*\{){5,}/ );
    }

    map { splice( @{ $sentences }, $_, 1 ) } @{ $prune_indices }

}

# update story vectors for the given story, updating story_sentences and story_sentence_words
# if no_delete is true, do not try to delete existing entries in the above table before creating new ones
# (useful for optimization if you are very sure no story vectors exist for this story).  If
# $no_dedup_sentences is true, do not perform sentence deduplication (useful if you are reprocessing a
# small set of stories)
sub update_story_sentence_words_and_language
{
    my ( $db, $story_ref, $no_delete, $no_dedup_sentences, $ignore_date_range ) = @_;
    my $sentence_word_counts;
    my $story = _get_story( $db, $story_ref );

    my $stories_id = $story->{ stories_id };

    unless ( $no_delete )
    {
        $db->query( "DELETE FROM story_sentence_words WHERE stories_id = ?",        $stories_id );
        $db->query( "DELETE FROM story_sentences WHERE stories_id = ?",             $stories_id );
        $db->query( "DELETE FROM story_sentence_counts WHERE first_stories_id = ?", $stories_id );
    }

    unless ( $ignore_date_range or _story_within_media_source_story_words_date_range( $db, $story ) )
    {
        say STDERR "Won't split story " .
          $stories_id . " " . "into sentences / words and determine their language because " .
          "story is *not* within media source's story words date range and 'ignore_date_range' is not set.";
        return;
    }

    # Get story text
    my $story_text = $story->{ story_text } || MediaWords::DBI::Stories::get_text_for_word_counts( $db, $story ) || '';
    my $story_description = $story->{ description } || '';

    if ( ( length( $story_text ) == 0 ) || ( length( $story_text ) < length( $story_description ) ) )
    {
        $story_text = html_strip( $story->{ title } );
        if ( $story->{ description } )
        {
            $story_text .= '.' unless ( $story_text =~ /\.\s*$/ );
            $story_text .= html_strip( $story->{ description } );
        }
    }

    ## TODO - The code below to retrieve the story_tld is buggy -- the assignment to the shadow $story_tld has no effect
    ## TO avoid confusion I'm commenting it out.
    ## Since we're going to reextract all comment with the new extractor, I'm going to deferr any decsion about fixing the bug until that
    ## point to avoid creating data artifacts do to language detection changes.

    # # Determine TLD
    # my $story_tld = '';
    # if ( defined( $story->{ url } ) )
    # {
    #     my $story_url = $story->{ url };
    #     my $story_tld = MediaWords::Util::IdentifyLanguage::tld_from_url( $story_url );
    # }
    # else
    # {
    #     say STDERR "Story's URL for story ID " . $stories_id . " is not defined.";
    # }

    # Identify the language of the full story
    my $story_lang = MediaWords::Util::IdentifyLanguage::language_code_for_text( $story_text, '' );

    my $sentences = _get_sentences_from_story_text( $story_text, $story_lang );

    if ( !$story->{ language } || ( $story_lang ne $story->{ language } ) )
    {
        $db->query( "UPDATE stories SET language = ? WHERE stories_id = ?", $story_lang, $stories_id );
    }

    unless ( defined $sentences )
    {
        die "Sentences for story $stories_id are undefined.";
    }
    unless ( scalar @{ $sentences } )
    {
        warn "Story $stories_id doesn't have any sentences.";
        return;
    }

    clean_sentences( $sentences );

    if ( $no_dedup_sentences )
    {
        say STDERR "Won't de-duplicate sentences for story $stories_id because 'no_dedup_sentences' is set.";
    }
    else
    {
        $sentences = dedup_sentences( $db, $story_ref, $sentences );
    }


    my $sentence_refs = [];
    for ( my $sentence_num = 0 ; $sentence_num < @{ $sentences } ; $sentence_num++ )
    {
        my $sentence = $sentences->[ $sentence_num ];

        # Identify the language of each of the sentences
        my $sentence_lang = MediaWords::Util::IdentifyLanguage::language_code_for_text( $sentence, '' );
        if ( $sentence_lang ne $story_lang )
        {

            # Mark the language as unknown if the results for the sentence are not reliable
            if ( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( $sentence ) )
            {
                $sentence_lang = '';
            }
        }

        # Insert the sentence into the database
        my $sentence_ref = {};
        $sentence_ref->{ sentence }        = $sentence;
        $sentence_ref->{ language }        = $sentence_lang;
        $sentence_ref->{ sentence_number } = $sentence_num;
        $sentence_ref->{ stories_id }      = $stories_id;
        $sentence_ref->{ media_id }        = $story->{ media_id };
        $sentence_ref->{ publish_date }    = $story->{ publish_date };

        push( @{ $sentence_refs }, $sentence_ref );
    }

    _insert_story_sentences( $db, $story, $sentence_refs );

    $db->dbh->{ AutoCommit } || $db->commit;

    if (    MediaWords::Util::CoreNLP::annotator_is_enabled()
        and MediaWords::Util::CoreNLP::story_is_annotatable( $db, $stories_id ) )
    {
        # (Re)enqueue for CoreNLP annotation
        #
        # We enqueue an identical job in MediaWords::DBI::Downloads::process_download_for_extractor() too,
        # but duplicate the enqueue_on_gearman() call here just to make sure that story gets reannotated
        # on each sentence change. Both of these jobs are to be merged into a single job by Gearman.
        MediaWords::GearmanFunction::AnnotateWithCoreNLP->enqueue_on_gearman( { stories_id => $stories_id } );

    }
}

sub _get_stem_word_counts_for_sentence($$;$)
{
    my ( $sentence, $sentence_lang, $fallback_lang ) = @_;

    # Determined sentence language
    my $lang =
         MediaWords::Languages::Language::language_for_code( $sentence_lang )
      || MediaWords::Languages::Language::language_for_code( $fallback_lang )
      || MediaWords::Languages::Language::default_language();

    my $words      = $lang->tokenize( $sentence );
    my $stop_stems = $lang->get_tiny_stop_word_stems();

    my $stems = $lang->stem( @{ $words } );

    my $word_counts = {};

    for ( my $word_num = 0 ; $word_num < @{ $words } ; $word_num++ )
    {
        my ( $word, $stem ) = ( $words->[ $word_num ], $stems->[ $word_num ] );

        my $word_length_limit = $lang->get_word_length_limit();
        if ( $word_length_limit > 0 )
        {
            limit_string_length( $word, $word_length_limit );
            limit_string_length( $stem, $word_length_limit );
        }

        if ( _valid_stem( $stem, $word, $stop_stems ) )
        {
            $word_counts->{ $stem }->{ word }     ||= $word;
            $word_counts->{ $stem }->{ language } ||= $sentence_lang;
            $word_counts->{ $stem }->{ language } ||= $fallback_lang;    # if no sentence_lang was set
            $word_counts->{ $stem }->{ count }++;
        }
    }

    return $word_counts;
}

# return a where clause that restricts the media_sets_id to the given media_sets_id or else
# adds no restriction at all if the media_sets_id is not defined
sub _get_media_set_clause
{
    my ( $media_sets_id ) = @_;

    if ( !defined( $media_sets_id ) )
    {
        return '1=1';
    }
    else
    {
        return "media_sets_id = $media_sets_id";
    }
}

# return a where clause that restricts the dashboard_topics_id to the given dashboard_topics_id or else
# adds no restriction at all if the dashboard_topics_id is not defined
sub _get_dashboard_topic_clause
{
    my ( $dashboard_topics_id ) = @_;

    if ( !defined( $dashboard_topics_id ) )
    {
        return '1=1';
    }
    else
    {
        return "dashboard_topics_id = $dashboard_topics_id";
    }
}

# return media_set and dashboard_topic update clauses
sub _get_update_clauses
{
    my ( $dashboard_topics_id, $media_sets_id ) = @_;

    my $d = _get_dashboard_topic_clause( $dashboard_topics_id );
    my $m = _get_media_set_clause( $media_sets_id );

    return "AND $d AND $m";
}

#
sub _update_total_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: total_weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query(
        <<"EOF"
        DELETE FROM total_weekly_words
        WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
              $update_clauses
EOF
    );

    $db->query_with_large_work_mem(
        <<"EOF"
        INSERT INTO total_weekly_words (
            media_sets_id,
            dashboard_topics_id,
            publish_week,
            total_count
        )
            SELECT media_sets_id,
                   dashboard_topics_id,
                   publish_week,
                   SUM(stem_count) AS total_count
            FROM weekly_words
            WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
                  $update_clauses
            GROUP BY media_sets_id,
                     dashboard_topics_id,
                     publish_week
            ORDER BY publish_week ASC,
                     media_sets_id,
                     dashboard_topics_id
EOF
    );
}

#
sub _sentence_study_update_total_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: total_weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    my $total_weekly_words_table = $sentence_study_table_prefix . 'total_weekly_words' . $sentence_study_table_suffix;
    my $weekly_words_table       = $sentence_study_table_prefix . 'weekly_words' . $sentence_study_table_suffix;

    $db->query(
        <<"EOF"
        DELETE FROM $total_weekly_words_table
        WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
              $update_clauses
EOF
    );

    $db->query_with_large_work_mem(
        <<"EOF"
        INSERT INTO $total_weekly_words_table (
            media_sets_id,
            dashboard_topics_id,
            publish_week,
            total_count
        )
            SELECT media_sets_id,
                   dashboard_topics_id,
                   publish_week,
                   SUM(stem_count) AS total_count
            FROM $weekly_words_table
            WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
                  $update_clauses
            GROUP BY media_sets_id,
                     dashboard_topics_id,
                     publish_week
            ORDER BY publish_week ASC,
                     media_sets_id,
                     dashboard_topics_id
EOF
    );
}

# update the top_500_weekly_words table with the 500 most common stop worded stems for each media_sets_id each week
sub _sentence_study_update_top_500_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: _sentence_study_update_top_500_weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    my $top_500_weekly_words_table = $sentence_study_table_prefix . 'top_500_weekly_words' . $sentence_study_table_suffix;
    my $total_top_500_weekly_words_table =
      $sentence_study_table_prefix . 'total_top_500_weekly_words' . $sentence_study_table_suffix;
    my $weekly_words_table = $sentence_study_table_prefix . 'weekly_words' . $sentence_study_table_suffix;

    $db->query(
        <<"EOF"
        DELETE FROM $top_500_weekly_words_table
        WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
              $update_clauses
EOF
    );
    $db->query(
        <<"EOF"
        DELETE FROM $total_top_500_weekly_words_table
        WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
              $update_clauses
EOF
    );

    #TODO figure out if regexp_replace( term, E'''s?\\\\Z', '' ) is really necessary

    # Note in postgresql [:alpha:] doesn't include international characters.
    # [^[:digit:][:punct:][:cntrl:][:space:]] is the closest equivalent to [:alpha:] to include international characters
    $db->query_with_large_work_mem(
        <<"EOF"
        INSERT INTO $top_500_weekly_words_table (
            media_sets_id,
            term,
            stem,
            stem_count,
            publish_week,
            dashboard_topics_id
        )
            SELECT media_sets_id,
                   REGEXP_REPLACE( term, E'''s?\\\\Z', '' ),
                   stem,
                   stem_count,
                   publish_week,
                   dashboard_topics_id
            FROM (SELECT media_sets_id,
                         term,
                         stem,
                         stem_count,
                         publish_week,
                         dashboard_topics_id,
                         RANK() OVER (
                             PARTITION BY media_sets_id, dashboard_topics_id
                             ORDER BY stem_count desc
                         ) AS stem_rank
                  FROM $weekly_words_table
                  WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
                        $update_clauses
                        AND NOT is_stop_stem( 'long', stem, null::text )
                        AND stem ~ '[^[:digit:][:punct:][:cntrl:][:space:]]'
            ) AS q
            WHERE stem_rank < 500
            ORDER BY stem_rank ASC
EOF
    );

    $db->query_with_large_work_mem(
        <<"EOF"
        INSERT INTO $total_top_500_weekly_words_table (
            media_sets_id,
            publish_week,
            total_count,
            dashboard_topics_id
        )
            SELECT media_sets_id,
                   publish_week,
                   SUM( stem_count ),
                   dashboard_topics_id
            FROM $top_500_weekly_words_table
            WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
                  $update_clauses
            GROUP BY media_sets_id,
                     publish_week,
                     dashboard_topics_id
EOF
    );
}

# update the top_500_weekly_words table with the 500 most common stop worded stems for each media_sets_id each week
sub _update_top_500_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: top_500_weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query(
        <<"EOF"
        DELETE FROM top_500_weekly_words
        WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
              $update_clauses
EOF
    );
    $db->query(
        <<"EOF"
        DELETE FROM total_top_500_weekly_words
        WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
              $update_clauses
EOF
    );

    #TODO figure out if regexp_replace( term, E'''s?\\\\Z', '' ) is really necessary

    # Note in postgresql [:alpha:] doesn't include international characters.
    # [^[:digit:][:punct:][:cntrl:][:space:]] is the closest equivalent to [:alpha:] to include international characters
    $db->query_with_large_work_mem(
        <<"EOF"
        INSERT INTO top_500_weekly_words (
            media_sets_id,
            term,
            stem,
            stem_count,
            publish_week,
            dashboard_topics_id
        )
            SELECT media_sets_id,
                   REGEXP_REPLACE( term, E'''s?\\\\Z', '' ),
                   stem,
                   stem_count,
                   publish_week,
                   dashboard_topics_id
            FROM (SELECT media_sets_id,
                         term,
                         stem,
                         stem_count,
                         publish_week,
                         dashboard_topics_id,
                         RANK() OVER (
                             PARTITION BY media_sets_id, dashboard_topics_id
                             ORDER BY stem_count DESC
                         ) AS stem_rank
                  FROM weekly_words
                  WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
                        $update_clauses
                        AND NOT is_stop_stem( 'long', stem, null::text )
                        AND stem ~ '[^[:digit:][:punct:][:cntrl:][:space:]]'
            ) AS q
            WHERE stem_rank < 500
            ORDER BY stem_rank ASC
EOF
    );

    $db->query_with_large_work_mem(
        <<"EOF"
        INSERT INTO total_top_500_weekly_words (
            media_sets_id,
            publish_week,
            total_count,
            dashboard_topics_id
        )
            SELECT media_sets_id,
                   publish_week,
                   SUM( stem_count ),
                   dashboard_topics_id
            FROM top_500_weekly_words
            WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
                  $update_clauses
            GROUP BY media_sets_id,
                     publish_week,
                     dashboard_topics_id
EOF
    );
}

# update the top_500_weekly_author_words table with the 500 most common stop worded stems for each media_sets_id each week
sub _update_top_500_weekly_author_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    return if ( $dashboard_topics_id || $media_sets_id );

    say STDERR "aggregate: top_500_weekly_author_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query(
        <<"EOF"
        DELETE FROM top_500_weekly_author_words
        WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
              $update_clauses
EOF
    );
    $db->query(
        <<"EOF"
        DELETE FROM total_top_500_weekly_author_words
        WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
              $update_clauses
EOF
    );

    # Note in postgresql [:alpha:] doesn't include international characters.
    # [^[:digit:][:punct:][:cntrl:][:space:]] is the closest equivalent to [:alpha:] to include international characters
    $db->query_with_large_work_mem(
        <<"EOF"
        INSERT INTO top_500_weekly_author_words (
            media_sets_id,
            term,
            stem,
            stem_count,
            publish_week,
            authors_id
        )
            SELECT media_sets_id,
                   REGEXP_REPLACE( term, E'''s?\\\\Z', '' ),
                   stem,
                   stem_count,
                   publish_week,
                   authors_id
            FROM (SELECT media_sets_id,
                         term,
                         stem,
                         stem_count,
                         publish_week,
                         authors_id,
                         RANK() OVER (
                             PARTITION BY media_sets_id, authors_id
                             ORDER BY stem_count DESC
                         ) AS stem_rank
                  FROM weekly_author_words
                  WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
                        $update_clauses
                        AND NOT is_stop_stem( 'long', stem, null::text )
                        AND stem ~ '[^[:digit:][:punct:][:cntrl:][:space:]]'
            ) AS q
            WHERE stem_rank < 500
            ORDER BY stem_rank ASC
EOF
    );

    $db->query_with_large_work_mem(
        <<"EOF"
        INSERT INTO total_top_500_weekly_author_words (
            media_sets_id,
            publish_week,
            total_count,
            authors_id
        )
            SELECT media_sets_id,
                   publish_week,
                   SUM( stem_count ),
                   authors_id
            FROM top_500_weekly_author_words
            WHERE publish_week = DATE_TRUNC( 'week', '$sql_date'::date )
                  $update_clauses
            GROUP BY media_sets_id,
                     publish_week,
                     authors_id
EOF
    );
}

# sub _update_daily_stories_counts
# {
#     my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

#     say STDERR "aggregate: update_daily_stories_counts $sql_date";

#     my $dashboard_topic_clause = _get_dashboard_topic_clause( $dashboard_topics_id );
#     my $media_set_clause       = _get_media_set_clause( $media_sets_id );
#     my $update_clauses         = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

#     $db->query( "DELETE FROM daily_story_count WHERE publish_day = '${ sql_date }'::date $update_clauses" );

#     #$db->query( "DELETE FROM daily_words WHERE publish_day = '${ sql_date }'::date $update_clauses" );
#     #$db->query(
#     #    "DELETE FROM total_daily_words WHERE publish_day = '${ sql_date }'::date $update_clauses" );

#     if ( !$dashboard_topics_id )
#     {

#         my $sql = <<"EOF";
# INSERT INTO daily_story_count (media_sets_id, dashboard_topics_id, publish_day, story_count)
#     SELECT media_sets_id,
#            NULL AS dashboard_topics_id,
#            MIN(publish_day) AS publish_day,
#            COUNT(*) AS story_count
#     FROM story_sentence_words AS ssw,
#          media_sets_media_map AS msmm
#     WHERE ssw.publish_day = '${sql_date}'::date
#           AND ssw.media_id = msmm.media_id
#           AND $media_set_clause
#     GROUP BY msmm.media_sets_id,
#              ssw.publish_day
# EOF

#         $db->query( $sql );

#     }

# }

# update the given table for the given date and interval
sub _update_daily_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: daily_words $sql_date";

    my $dashboard_topic_clause = _get_dashboard_topic_clause( $dashboard_topics_id );
    my $media_set_clause       = _get_media_set_clause( $media_sets_id );
    my $update_clauses         = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query(
        <<"EOF"
        DELETE FROM daily_words
        WHERE publish_day = '${ sql_date }'::date
              $update_clauses
EOF
    );
    $db->query(
        <<"EOF"
        DELETE FROM total_daily_words
        WHERE publish_day = '${ sql_date }'::date
              $update_clauses
EOF
    );

    if ( !$dashboard_topics_id )
    {
        $db->query_with_large_work_mem(
            <<"EOF"
            INSERT INTO daily_words (
                media_sets_id,
                term,
                stem,
                stem_count,
                publish_day,
                dashboard_topics_id
            )
                SELECT media_sets_id,
                       term,
                       stem,
                       sum_stem_counts,
                       publish_day,
                       NULL AS dashboard_topics_id
                FROM (SELECT media_sets_id,
                             term,
                             stem,
                             stem_count_sum,
                             publish_day,
                             NULL,
                             RANK() OVER (w ORDER BY stem_count_sum DESC, term DESC) AS term_rank,
                             SUM(stem_count_sum) OVER w AS sum_stem_counts
                      FROM (SELECT media_sets_id,
                                   term,
                                   stem,
                                   SUM(stem_count) AS stem_count_sum,
                                   MIN(publish_day) AS publish_day,
                                   NULL
                            FROM story_sentence_words AS ssw
                                    INNER JOIN story_sentences AS ss
                                        ON ssw.stories_id = ss.stories_id AND ssw.sentence_number = ss.sentence_number,
                                 media_sets_media_map AS msmm
                            WHERE ssw.publish_day = '${sql_date}'::date
                                  AND ssw.media_id = msmm.media_id
                                  AND $media_set_clause
                            GROUP BY msmm.media_sets_id,
                                     ssw.stem,
                                     ssw.term
                      ) AS foo WINDOW w AS (PARTITION BY media_sets_id, stem, publish_day )
                ) AS q
                WHERE term_rank = 1
EOF
        );
    }

    my $dashboard_topics = $db->query(
        <<"EOF"
        SELECT *
        FROM dashboard_topics
        WHERE 1=1 AND $dashboard_topic_clause
EOF
    )->hashes;

    for my $dashboard_topic ( @{ $dashboard_topics } )
    {
        my $query_2 = <<"EOF";
            INSERT INTO daily_words (
                media_sets_id,
                term,
                stem,
                stem_count,
                publish_day,
                dashboard_topics_id
            )
                SELECT media_sets_id,
                       term,
                       stem,
                       sum_stem_counts,
                       publish_day,
                       dashboard_topics_id
                FROM (SELECT media_sets_id,
                             term,
                             stem,
                             stem_count_sum,
                             publish_day,
                             dashboard_topics_id,
                             RANK() OVER (w ORDER BY stem_count_sum DESC, term DESC) AS term_rank,
                             SUM(stem_count_sum) OVER w AS sum_stem_counts
                      FROM (SELECT media_sets_id,
                                   ssw.term AS term,
                                   ssw.stem AS stem,
                                   SUM(ssw.stem_count) AS stem_count_sum,
                                   MIN(ssw.publish_day) AS publish_day,
                                   ?::integer AS dashboard_topics_id
                            FROM story_sentence_words AS ssw
                                    INNER JOIN story_sentences AS ss
                                        ON ssw.stories_id = ss.stories_id AND ssw.sentence_number = ss.sentence_number,
                                 (SELECT media_sets_id,
                                         stories_id,
                                         sentence_number
                                  FROM story_sentence_words AS sswq,
                                       media_sets_media_map AS msmm
                                  WHERE sswq.media_id = msmm.media_id
                                        AND sswq.stem = ?
                                        AND sswq.publish_day = ?
                                        AND $media_set_clause
                                  GROUP BY msmm.media_sets_id,
                                           stories_id,
                                           sentence_number
                                 ) AS ssw_sentences_for_query
                            WHERE ssw.stories_id=ssw_sentences_for_query.stories_id
                                  AND ssw.sentence_number=ssw_sentences_for_query.sentence_number
                            GROUP BY media_sets_id,
                                     ssw.stem,
                                     term
                           ) AS foo WINDOW w AS (PARTITION BY media_sets_id, stem, publish_day )
                     ) AS q
                WHERE term_rank = 1
EOF

        # doing these one by one is the only way I could get the postgres planner to create
        # a sane plan
        $db->query_with_large_work_mem(
            $query_2,
            $dashboard_topic->{ dashboard_topics_id },
            $dashboard_topic->{ query }, $sql_date
        );
    }

    $db->query_with_large_work_mem(
        <<"EOF"
        INSERT INTO total_daily_words (
            media_sets_id,
            publish_day,
            total_count,
            dashboard_topics_id
        )
            SELECT media_sets_id,
                   publish_day,
                   SUM(stem_count),
                   dashboard_topics_id
            FROM daily_words
            WHERE publish_day = '${sql_date}'::date
                  $update_clauses
            GROUP BY media_sets_id,
                     publish_day,
                     dashboard_topics_id
EOF
    );

    return 1;
}

# update the given table for the given date and interval
sub _update_daily_author_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    return if ( $dashboard_topics_id || $media_sets_id );

    say STDERR "aggregate: update_daily_author_words $sql_date";

    my $dashboard_topic_clause = _get_dashboard_topic_clause( $dashboard_topics_id );
    my $media_set_clause       = _get_media_set_clause( $media_sets_id );
    my $update_clauses         = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $update_clauses = '';

    $db->query(
        <<"EOF"
        DELETE FROM daily_author_words
        WHERE publish_day = DATE_TRUNC( 'day', '${ sql_date }'::date )
              $update_clauses
EOF
    );

    $db->query(
        <<"EOF"
        DELETE FROM total_daily_author_words
        WHERE publish_day = DATE_TRUNC( 'day', '${ sql_date }'::date )
              $update_clauses
EOF
    );

    my $query = <<"EOF";

        INSERT INTO daily_author_words (
            authors_id,
            media_sets_id,
            term,
            stem,
            stem_count,
            publish_day
        )
            SELECT authors_id,
                   media_sets_id,
                   term,
                   stem,
                   sum_stem_counts,
                   publish_day
            FROM (SELECT authors_id,
                         media_sets_id,
                         term,
                         stem,
                         stem_count_sum,
                         publish_day,
                         RANK() OVER (w ORDER BY stem_count_sum DESC, term DESC) AS term_rank,
                         SUM(stem_count_sum) OVER w AS sum_stem_counts
                  FROM (SELECT authors_id,
                               media_sets_id,
                               term,
                               stem,
                               SUM(stem_count) AS stem_count_sum,
                               MIN(publish_day) AS publish_day,
                               NULL
                        FROM story_sentence_words AS ssw
                                    INNER JOIN story_sentences AS ss
                                        ON ssw.stories_id = ss.stories_id AND ssw.sentence_number = ss.sentence_number,
                             media_sets_media_map AS msmm,
                             authors_stories_map
                        WHERE ssw.publish_day = '${sql_date}'::date
                              AND ssw.stories_id = authors_stories_map.stories_id
                              AND ssw.media_id = msmm.media_id
                        GROUP BY msmm.media_sets_id,
                                 ssw.stem,
                                 ssw.term,
                                 authors_id
                       ) AS foo WINDOW w AS (PARTITION BY media_sets_id, stem, publish_day )
                 ) AS query
            WHERE term_rank = 1
                  AND sum_stem_counts > 1
EOF

    $db->query_with_large_work_mem( $query );

    say STDERR "Completed query $query";

    $db->query_with_large_work_mem(
        <<"EOF"
        INSERT INTO total_daily_author_words (
            authors_id,
            media_sets_id,
            publish_day,
            total_count
        )
            SELECT authors_id,
                   media_sets_id,
                   publish_day,
                   SUM(stem_count) AS total_count
            FROM daily_author_words
            WHERE publish_day = '${sql_date}'::date
                  $update_clauses
            GROUP BY authors_id,
                     media_sets_id,
                     publish_day
EOF
    );

    return 1;
}

# update the given table for the given date and interval
sub _update_daily_country_counts
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    # disabling this rather than fixing it temporarily to remove the language stuff
    # because we'll be obsoleting it when we move to lucene in any case - hal 2013-07-15
    return 1;

    return 1 if ( $dashboard_topics_id );

    my $media_set_clause = _get_media_set_clause( $media_sets_id );

    $db->query(
        <<"EOF"
        DELETE FROM daily_country_counts
        WHERE publish_day = '${ sql_date }'::date
              AND $media_set_clause
EOF
    );

    # For all configured languages
    my @enabled_languages = MediaWords::Languages::Language::enabled_languages();
    foreach my $language_code ( @enabled_languages )
    {
        my $all_countries = MediaWords::Util::Countries::get_countries_for_counts( $language_code );

        my $stemmed_country_terms =
          [ map { MediaWords::Util::Countries::get_stemmed_country_terms( $_, $language_code ) } @{ $all_countries } ];

        my $single_terms_list =
          join( ',', map { $db->dbh->quote( $_->[ 0 ] ) } grep { @{ $_ } == 1 } @{ $stemmed_country_terms } );

        $db->query_with_large_work_mem(
            <<"EOF"
            INSERT INTO daily_country_counts (
                media_sets_id,
                language,
                publish_day,
                country,
                country_count
            )
                SELECT media_sets_id,
                       '$language_code',
                       publish_day,
                       stem,
                       stem_count
                FROM daily_words
                WHERE publish_day = '$sql_date'::date
                      AND dashboard_topics_id IS NULL
                      AND $media_set_clause
                      AND stem IN ( $single_terms_list )
EOF
        );

        my $double_country_terms = [ grep { @{ $_ } == 2 } @{ $stemmed_country_terms } ];

        for my $country ( @{ $double_country_terms } )
        {
            my $country_name = join( " ", @{ $country } );
            my ( $term_a, $term_b ) = map { $db->dbh->quote( $_ ) } @{ $country };

            $db->query_with_large_work_mem(
                <<"EOF",
                INSERT INTO daily_country_counts (
                    media_sets_id,
                    language,
                    publish_day,
                    country,
                    country_count
                )
                    SELECT msmm.media_sets_id,
                           '$language_code',
                           ssw.publish_day,
                           ?,
                           COUNT(*)
                    FROM story_sentence_words AS ssw,
                         media_sets_media_map AS msmm
                    WHERE ssw.media_id = msmm.media_id
                          AND ssw.publish_day = '$sql_date'::date
                          AND stem = $term_a
                          AND language = '$language_code'
                          AND EXISTS (SELECT 1
                                      FROM story_sentence_words AS sswb
                                      WHERE ssw.publish_day = sswb.publish_day
                                            AND ssw.media_id = sswb.media_id
                                            AND sswb.stem = $term_b
                                            AND sswb.language = '$language_code'
                                            AND ssw.stories_id = sswb.stories_id
                                            AND ssw.sentence_number = sswb.sentence_number
                                     )
                    GROUP BY msmm.media_sets_id,
                             ssw.publish_day
EOF
                $country_name
            );
        }

    }

    return 1;
}

# get quoted, comma separate list of the dates in the week starting with
# the given date
sub _get_week_dates_list
{
    my ( $start_date ) = @_;

    my $dates = [ $start_date ];
    for my $i ( 1 .. 6 )
    {
        push( @{ $dates }, MediaWords::Util::SQL::increment_day( $start_date, $i ) );
    }

    return join( ',', map { "'$_'::date" } @{ $dates } );
}

# update the given table for the given date and interval
sub _update_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    my ( $week_start_date ) = $db->query( "SELECT week_start_date( '${ sql_date }'::date ) " )->flat;

    $sql_date = $week_start_date;

    # use an in list of dates instead of sql between b/c postgres is really slow using
    # between for dates
    my $week_dates = _get_week_dates_list( $sql_date );

    $db->query_with_large_work_mem(
        <<"EOF"
        DELETE FROM weekly_words
        WHERE publish_week = '${ sql_date }'::date
              AND media_sets_id IN (SELECT DISTINCT(media_sets_id)
                                    FROM total_daily_words
                                    WHERE week_start_date(publish_day) = '${ sql_date }'::date
                                   )
              $update_clauses
EOF
    );

    my $query = <<"EOF";
        INSERT INTO weekly_words (
            media_sets_id,
            term,
            stem,
            stem_count,
            publish_week,
            dashboard_topics_id
        )
            SELECT media_sets_id,
                   term,
                   stem,
                   sum_stem_counts,
                   publish_week,
                   dashboard_topics_id
            FROM (SELECT media_sets_id,
                         term,
                         stem,
                         stem_count_sum,
                         publish_week,
                         dashboard_topics_id,
                         RANK() OVER (w ORDER BY stem_count_sum DESC, term DESC) AS term_rank,
                         SUM(stem_count_sum) OVER w AS sum_stem_counts
                  FROM (SELECT media_sets_id,
                               term,
                               stem,
                               SUM(stem_count) AS stem_count_sum,
                               '${ sql_date }'::date AS publish_week,
                               dashboard_topics_id
                        FROM daily_words
                        WHERE week_start_date(publish_day) = '${ sql_date }'::date
                              $update_clauses
                        GROUP BY media_sets_id,
                                 stem,
                                 term,
                                 dashboard_topics_id
                       ) AS foo WINDOW w AS (PARTITION BY media_sets_id, stem, publish_week, dashboard_topics_id )
                 ) AS q
            WHERE term_rank = 1
EOF

    #say STDERR "query:\n$query";
    $db->query_with_large_work_mem( $query );

    return 1;
}

# update the given table for the given date and interval
sub _sentence_study_update_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: _sentence_study_update_weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    my ( $week_start_date ) = $db->query( " SELECT week_start_date( '${ sql_date }'::date ) " )->flat;

    $sql_date = $week_start_date;

    # use an in list of dates instead of sql between b/c postgres is really slow using
    # between for dates
    my $week_dates = _get_week_dates_list( $sql_date );

    my $table_prefix = 'sen_study_new_';
    my $table_suffix = '_2011_01_03_2011_01_10';

    my $weekly_words_table = $sentence_study_table_prefix . 'weekly_words' . $sentence_study_table_suffix;
    my $daily_words_table  = $sentence_study_table_prefix . 'daily_words' . $sentence_study_table_suffix;

    say STDERR "Delete query ";

    $db->query(
        <<"EOF"
        DELETE FROM $weekly_words_table
        WHERE publish_week = '${ sql_date }'::date
              $update_clauses
EOF
    );

    my $query = <<"EOF";
        INSERT INTO $weekly_words_table (
            media_sets_id,
            term,
            stem,
            stem_count,
            publish_week,
            dashboard_topics_id
        )
            SELECT media_sets_id,
                   term,
                   stem,
                   sum_stem_counts,
                   publish_week,
                   dashboard_topics_id
            FROM (SELECT media_sets_id,
                         term,
                         stem,
                         stem_count_sum,
                         publish_week,
                         dashboard_topics_id,
                         RANK() OVER (w ORDER BY stem_count_sum DESC, term DESC) AS term_rank,
                         SUM(stem_count_sum) OVER w AS sum_stem_counts
                  FROM (SELECT media_sets_id,
                             term,
                             stem,
                             SUM(stem_count) AS stem_count_sum,
                             '${ sql_date }'::date AS publish_week,
                             dashboard_topics_id
                      FROM $daily_words_table
                      WHERE week_start_date(publish_day) = '${ sql_date }'::date
                            $update_clauses
                      GROUP BY media_sets_id,
                               stem,
                               term,
                               dashboard_topics_id
                     ) AS foo WINDOW w AS (PARTITION BY media_sets_id, stem, publish_week, dashboard_topics_id )
                 ) AS q
            WHERE term_rank = 1
EOF

    say STDERR "insert_query: '$query'";

    #say STDERR "query:\n$query";
    $db->query( $query );

    return 1;
}

# update the given table for the given date and interval
sub _update_weekly_author_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    return if ( $dashboard_topics_id || $media_sets_id );

    say STDERR "aggregate: weekly_author_words $sql_date";

    #TODO get rid of dashboards_id from this query
    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query_with_large_work_mem(
        <<"EOF"
        DELETE FROM weekly_author_words
        WHERE publish_week = DATE_TRUNC( 'week', '${ sql_date }'::date )
              $update_clauses
EOF
    );

    my $query = <<"EOF";
        INSERT INTO weekly_author_words (
            authors_id,
            media_sets_id,
            term,
            stem,
            stem_count,
            publish_week
        )
            SELECT authors_id,
                   media_sets_id,
                   term,
                   stem,
                   sum_stem_counts,
                   publish_week
            FROM (SELECT media_sets_id,
                         term,
                         stem,
                         stem_count_sum,
                         publish_week,
                         authors_id,
                         RANK() OVER (w ORDER BY stem_count_sum DESC, term DESC) AS term_rank,
                         SUM(stem_count_sum) OVER w AS sum_stem_counts
                  FROM (SELECT media_sets_id,
                               term,
                               stem,
                               SUM(stem_count) AS stem_count_sum,
                               DATE_TRUNC('week', MIN(publish_day)) AS publish_week,
                               authors_id
                        FROM daily_author_words
                        WHERE publish_day BETWEEN DATE_TRUNC('week', '${sql_date}'::date) AND DATE_TRUNC('week', '${sql_date}'::date ) + INTERVAL '6 days'
                              $update_clauses
                        GROUP BY media_sets_id,
                                 stem,
                                 term,
                                 authors_id
                       ) AS foo WINDOW w AS (PARTITION BY media_sets_id, stem, publish_week, authors_id )
                 ) AS q
            WHERE term_rank = 1
EOF

    say STDERR "running weekly_author_words query:$query";

    $db->query_with_large_work_mem( $query );

    return 1;
}

# return true if the date exists in the daily_words table
sub _aggregate_data_exists_for_date
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    my $update_clauses;

    # specifically look for null dashboard_topics_id so that the aggregator doesn't
    # skip a daily run because a new topic has been added with data for just that topic
    # for the day
    if ( !$dashboard_topics_id )
    {
        $update_clauses = " AND dashboard_topics_id IS NULL";
        if ( $media_sets_id )
        {
            $update_clauses .= " AND media_sets_id = $media_sets_id";
        }
    }
    else
    {
        $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );
    }

    return $db->query(
        <<"EOF"
        SELECT 1 AS c
        FROM daily_words
        WHERE publish_day = DATE_TRUNC( 'day', DATE '$sql_date' )
              $update_clauses
        LIMIT 1
EOF
    )->hash;
}

# return true if the date exists in the daily_words table
sub _story_data_exists_for_date
{
    my ( $db, $sql_date, $media_sets_id ) = @_;

    # print STDERR "starting  _story_data_exists_for_date with date $sql_date ";

    # if ( $media_sets_id )
    # {
    #     say STDERR " AND media_sets_id $media_sets_id";
    # }
    # else
    # {
    #     say STDERR;
    # }

    my $media_set_clause = '';

    if ( $media_sets_id )
    {
        $media_set_clause = <<"EOF";
            media_id IN (
                SELECT media_id
                FROM media_sets_media_map
                WHERE media_sets_id = 11752
            )
EOF
    }
    else
    {
        $media_set_clause = " 1=1 ";
    }
    my $query = <<"EOF";
        SELECT 1
        FROM story_sentences
        WHERE DATE_TRUNC('day', publish_date)  = '$sql_date'
              AND $media_set_clause
        LIMIT 1
EOF

    # say STDERR "query: $query";

    my $ret = $db->query( $query )->hash;

    # say STDERR Dumper( $ret );
    # say STDERR "returning $ret";

    return $ret;
}

# add one day to the date in sql format
# use a postgres query to make sure we're doing the same thing as postgres, including dst
sub _increment_day
{
    my ( $date ) = @_;

    my $new_date = Date::Format::time2str( "%Y-%m-%d", Date::Parse::str2time( $date ) + 100000 );
}

#Convert the date to YYYY-MM-DD format is necessary and get rid of hours and minutes
sub _truncate_as_day
{
    my ( $date ) = @_;

    my $new_date = Date::Format::time2str( "%Y-%m-%d", Date::Parse::str2time( $date ) );

    return $new_date;
}

sub _date_is_sunday
{
    my ( $date ) = @_;

    return !( localtime( Date::Parse::str2time( $date ) ) )[ 6 ];
}

# update daily_words, weekly_words, and top_500_weekly_words tables for all included dates
# for which daily_words data does not already exist
#
# if dashbaord_topics_id or media_sets_id are specified, only update for the given
# dashboard_topic or media_set
sub update_aggregate_words($;$$$$$)
{
    my ( $db, $start_date, $end_date, $force, $dashboard_topics_id, $media_sets_id ) = @_;

    $start_date ||= '2008-06-01';
    $end_date ||= Date::Format::time2str( "%Y-%m-%d", time - 86400 );

    say STDERR "update_aggregate_words start_date: '$start_date' end_date: '$end_date' ";

    $start_date = _truncate_as_day( $start_date );
    $end_date   = _truncate_as_day( $end_date );

    my $days          = 0;
    my $update_weekly = 0;

    for ( my $date = $start_date ; $date le $end_date ; $date = _increment_day( $date ) )
    {
        say STDERR "update_aggregate_words: $date ($start_date - $end_date) $days";

        #_update_daily_stories_counts( $db, $date, $dashboard_topics_id, $media_sets_id );

        if (
            $force
            || ( ( !_aggregate_data_exists_for_date( $db, $date, $dashboard_topics_id, $media_sets_id ) )
                && _story_data_exists_for_date( $db, $date, $media_sets_id ) )
          )
        {
            say STDERR "update_aggregate_words: add for $date ($start_date - $end_date) $days";
            _update_daily_words( $db, $date, $dashboard_topics_id, $media_sets_id );

            #_update_daily_country_counts( $db, $date, $dashboard_topics_id, $media_sets_id );
            _update_daily_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            $update_weekly = 1;
        }
        else
        {
            say STDERR "update_aggregate_words: skipping because data exists for $date ($start_date - $end_date) $days";
        }

        # update weeklies either if there was a daily update for the week and if we are at the end of the date range
        # or the end of a week
        if ( $update_weekly && ( ( $date eq $end_date ) || _date_is_sunday( $date ) ) )
        {
            _update_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            _update_total_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            _update_top_500_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );

            _update_weekly_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            _update_top_500_weekly_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            $update_weekly = 0;
        }

        $db->dbh->{ AutoCommit } || $db->commit();

        $days++;
    }

    $db->dbh->{ AutoCommit } || $db->commit;
}

sub update_aggregate_author_words
{
    my ( $db, $start_date, $end_date, $force, $dashboard_topics_id, $media_sets_id ) = @_;

    $start_date ||= '2008-06-01';
    $end_date ||= Date::Format::time2str( "%Y-%m-%d", time - 86400 );

    $start_date = _truncate_as_day( $start_date );
    $end_date   = _truncate_as_day( $end_date );

    my $days          = 0;
    my $update_weekly = 0;

    for ( my $date = $start_date ; $date le $end_date ; $date = _increment_day( $date ) )
    {
        say STDERR "update_aggregate_words: $date ($start_date - $end_date) $days";

        $update_weekly = 1;

        {
            _update_daily_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
        }

        # update weeklies either if there was a daily update for the week and if we are at the end of the date range
        # or the end of a week
        if ( $update_weekly && ( ( $date eq $end_date ) || _date_is_sunday( $date ) ) )
        {
            {
                _update_weekly_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
                _update_top_500_weekly_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            }
            $update_weekly = 0;
        }

        $db->commit();

        $days++;
    }

    $db->commit;
}

sub update_aggregate_words_for_sentence_study
{
    my ( $db, $start_date, $end_date, $force, $dashboard_topics_id, $media_sets_id ) = @_;

    $start_date ||= '2008-06-01';
    $end_date ||= Date::Format::time2str( "%Y-%m-%d", time - 86400 );

    say STDERR "update_aggregate_words_for_sentence_study start_date: '$start_date' end_date:'$end_date' ";

    $start_date = _truncate_as_day( $start_date );
    $end_date   = _truncate_as_day( $end_date );

    my $days          = 0;
    my $update_weekly = 0;

    for ( my $date = $start_date ; $date le $end_date ; $date = _increment_day( $date ) )
    {
        say STDERR "update_aggregate_words: $date ($start_date - $end_date) $days";

        #_update_daily_stories_counts( $db, $date, $dashboard_topics_id, $media_sets_id );

        if ( $force || !_aggregate_data_exists_for_date( $db, $date, $dashboard_topics_id, $media_sets_id ) )
        {

            # _update_daily_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            # _update_daily_country_counts( $db, $date, $dashboard_topics_id, $media_sets_id );
            # _update_daily_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            # $update_weekly = 1;
        }

        $update_weekly = 1;

        # update weeklies either if there was a daily update for the week and if we are at the end of the date range
        # or the end of a week
        if ( $update_weekly && ( ( $date eq $end_date ) || _date_is_sunday( $date ) ) )
        {
            _sentence_study_update_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            _sentence_study_update_total_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            _sentence_study_update_top_500_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );

            # _update_weekly_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            # _update_top_500_weekly_author_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            $update_weekly = 0;
        }

        $db->commit();

        $days++;
    }

    $db->commit;
}

# if dashbaord_topics_id or media_sets_id are specified, only update for the given
# dashboard_topic or media_set
sub update_country_counts
{

    # disabling this rather than fixing it temporarily to remove the language stuff
    # because we'll be obsoleting it when we move to lucene in any case - hal 2013-07-15
    return;

    my ( $db, $start_date, $end_date, $force, $dashboard_topics_id, $media_sets_id ) = @_;

    $start_date ||= '2008-06-01';
    $end_date ||= Date::Format::time2str( "%Y-%m-%d", time - 86400 );

    my $days          = 0;
    my $update_weekly = 0;

    for ( my $date = $start_date ; $date le $end_date ; $date = _increment_day( $date ) )
    {
        say STDERR "update_aggregate_country_counts: $date ($start_date - $end_date) $days";

        if ( $force || !_aggregate_data_exists_for_date( $db, $date, $dashboard_topics_id, $media_sets_id ) )
        {
            _update_daily_country_counts( $db, $date, $dashboard_topics_id, $media_sets_id );
            $update_weekly = 1;
        }

        $db->commit();

        $days++;
    }

    $db->commit;
}

1;
