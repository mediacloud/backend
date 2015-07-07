package MediaWords::StoryVectors;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# methods to generate the story_sentences and associated aggregated tables

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

use constant MIN_STEM_LENGTH => 3;

Readonly my $sentence_study_table_prefix => 'sen_study_old_';
Readonly my $sentence_study_table_suffix => '_2011_01_03_2011_01_10';

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

    my $fields = [ qw/stories_id sentence_number sentence language publish_date media_id disable_triggers / ];
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

# get unique sentences from the list, maintaining the original order
sub _get_unique_sentences
{
    my ( $sentences ) = @_;

    my $unique_sentences       = [];
    my $unique_sentence_lookup = {};
    for my $sentence ( @{ $sentences } )
    {
        if ( !$unique_sentence_lookup->{ $sentence } )
        {
            $unique_sentence_lookup->{ $sentence } = 1;
            push( @{ $unique_sentences }, $sentence );
        }
    }

    return $unique_sentences;
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

    my $unique_sentences = _get_unique_sentences( $sentences );

    my $sentence_md5_lookup = {};
    my $i                   = 0;
    for my $sentence ( @{ $unique_sentences } )
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
    for ( my $i = 0 ; $i < @{ $sentences } ; $i++ )
    {
        push( @{ $prune_indices }, $i ) if ( $sentences->[ $i ] =~ /(\[.*\{){5,}/ );
    }

    map { splice( @{ $sentences }, $_, 1 ) } @{ $prune_indices }

}

# update story vectors for the given story, updating story_sentences
# if no_delete is true, do not try to delete existing entries in the above table before creating new ones
# (useful for optimization if you are very sure no story vectors exist for this story).  If
# $no_dedup_sentences is true, do not perform sentence deduplication (useful if you are reprocessing a
# small set of stories)
sub update_story_sentences_and_language
{
    my ( $db, $story, $no_delete, $no_dedup_sentences, $ignore_date_range ) = @_;

    die unless ref $story;
    die unless $story->{ stories_id };

    my $sentence_word_counts;

    my $stories_id = $story->{ stories_id };

    unless ( $no_delete )
    {
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
        $sentences = dedup_sentences( $db, $story, $sentences );
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
        $sentence_ref->{ sentence }         = $sentence;
        $sentence_ref->{ language }         = $sentence_lang;
        $sentence_ref->{ sentence_number }  = $sentence_num;
        $sentence_ref->{ stories_id }       = $stories_id;
        $sentence_ref->{ media_id }         = $story->{ media_id };
        $sentence_ref->{ publish_date }     = $story->{ publish_date };
        $sentence_ref->{ disable_triggers } = MediaWords::DB::story_triggers_disabled();

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

##NOTE: This method is only used by the test suite, consider removing it. - 04/07/2015
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

1;
