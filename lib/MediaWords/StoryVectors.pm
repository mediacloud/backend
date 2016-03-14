package MediaWords::StoryVectors;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# methods to generate the story_sentences and associated aggregated tables

use strict;
use warnings;

use Data::Dumper;

use MediaWords::Languages::Language;
use MediaWords::DBI::Stories;
use MediaWords::DBI::Stories::AP;
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

Readonly my $MIN_STEM_LENGTH => 3;

Readonly my $sentence_study_table_prefix => 'sen_study_old_';
Readonly my $sentence_study_table_suffix => '_2011_01_03_2011_01_10';

# return 1 if the stem passes various tests
sub _valid_stem
{
    my ( $stem, $word, $stop_stems ) = @_;

    return ( $stem
          && ( length( $stem ) >= $MIN_STEM_LENGTH )
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
sub _limit_string_length
{

    # my ( $s, $l ) = @_;

    if ( length( $_[ 0 ] ) > $_[ 1 ] )
    {
        substr( $_[ 0 ], $_[ 1 ] ) = '';
    }
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

# given the story and its un-deduped sentences, return the list of sentences that already
# exist in the same media source for the same calendar week.  fetch the sentences using the appropriate
# query based on whether the sentences are indexed by story_sentences_dup.  if do_update is true,
# set is_dup = true for the original versions of any dup sentences discovered.
sub get_dup_story_sentences
{
    my ( $db, $story, $sentences, $do_update ) = @_;

    my ( $indexdef ) = $db->query( "select indexdef from pg_indexes where indexname = 'story_sentences_dup'" )->flat;

    die( "'story_sentences_dup' index does not exist" ) unless ( $indexdef );

    die( "unable to find date in story_sentences_dup definition" ) unless ( $indexdef =~ /(\d\d\d\d-\d\d-\d\d)/ );

    # the date will get truncated to the monday of the current date, so only use consider the index date
    # starting with the monday of or following the index date
    my $index_date = MediaWords::Util::SQL::increment_to_monday( $1 );

    # we need to manually quote and include this date so that postgres will know to use the
    # conditional story_sentences_dup index
    my $q_publish_date = $db->dbh->quote( $story->{ publish_date } );

    my ( $sentence_lookup_clause, $date_clause );

    if ( $story->{ publish_date } gt $index_date )
    {
        my $q_sentence_md5s = [ map { $db->dbh->quote( Digest::MD5::md5_hex( encode( 'utf8', $_ ) ) ) } @{ $sentences } ];
        my $sentence_md5_list = join( ',', @{ $q_sentence_md5s } );

        $sentence_lookup_clause = "md5( sentence ) in ( $sentence_md5_list )";
        $date_clause            = "week_start_date( publish_date::date ) = week_start_date( ${ q_publish_date }::date )";
    }
    else
    {
        my $q_sentences = [ map { $db->dbh->quote( encode( 'utf8', $_ ) ) } @{ $sentences } ];
        my $sentence_list = join( ',', @{ $q_sentences } );

        $sentence_lookup_clause = "sentence in ( $sentence_list )";
        $date_clause            = <<SQL;
date_trunc( 'day', publish_date )
    between week_start_date( ${ q_publish_date }::date ) and
        week_start_date( ${ q_publish_date }::date ) + interval '6 days' and
    media_id = $story->{ media_id }
SQL
    }

    # we have to use this odd 'with ssd ...' form of the query to force postgres not to generate a plan
    # that tries to do a full scan of all the story_sentences_media_id entries for the media_id
    my $with_clause = <<SQL;
with ssd as (
            select story_sentences_id, media_id
            from story_sentences
            where $sentence_lookup_clause and
                $date_clause
)
SQL

    my $query;
    if ( $do_update )
    {
        $query = <<SQL;
$with_clause

update story_sentences ss set is_dup = true, disable_triggers = true
        from ssd
        where
            ssd.story_sentences_id = ss.story_sentences_id and
            ssd.media_id = $story->{ media_id }
    returning *
SQL
    }
    else
    {
        $query = <<SQL;
$with_clause

select *
        from story_sentences ss, ssd
        where
            ssd.story_sentences_id = ss.story_sentences_id and
            ssd.media_id = $story->{ media_id }
    returning *
SQL
    }

    return $db->query( $query )->hashes;
}

# return the sentences from the set that are dups within the same media source and calendar week.
# also sets story_sentences.dup to true for sentences that are the dups for these sentences.
sub get_deduped_sentences
{
    my ( $db, $story, $sentences ) = @_;

    my $unique_sentences = _get_unique_sentences( $sentences );

    my $dup_story_sentences = get_dup_story_sentences( $db, $story, $unique_sentences, 1 );

    my $dup_lookup = {};
    map { $dup_lookup->{ $_->{ sentence } } = 1 } @{ $dup_story_sentences };

    my $deduped_sentences = [ grep { !$dup_lookup->{ $_ } } @{ $unique_sentences } ];

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

    my $deduped_sentences = get_deduped_sentences( $db, $story, $sentences );

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

    my $medium = $db->query( "select * from media where media_id = ?", $story->{ media_id } )->hash;

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

# detect whether the story is syndicated and update stories.ap_syndicated
sub _update_ap_syndicated
{
    my ( $db, $story ) = @_;

    return unless ( $story->{ language } && $story->{ language } eq 'en' );

    my $ap_syndicated = MediaWords::DBI::Stories::AP::is_syndicated( $db, $story );

    $db->query( "delete from stories_ap_syndicated where stories_id = \$1", $story->{ stories_id } );

    $db->query( <<SQL, $story->{ stories_id }, $ap_syndicated );
insert into stories_ap_syndicated ( stories_id, ap_syndicated ) values ( \$1, \$2 )
SQL

    $story->{ ap_syndicated } = $ap_syndicated;
}

# given a list of text sentences, return a list of story_sentences refs for insertion into db.
sub _get_story_sentence_refs
{
    my ( $sentences, $story ) = @_;

    my $sentence_refs = [];
    for ( my $sentence_num = 0 ; $sentence_num < @{ $sentences } ; $sentence_num++ )
    {
        my $sentence = $sentences->[ $sentence_num ];

        # Identify the language of each of the sentences
        my $sentence_lang = MediaWords::Util::IdentifyLanguage::language_code_for_text( $sentence, '' );
        if ( $sentence_lang ne $story->{ language } )
        {

            # Mark the language as unknown if the results for the sentence are not reliable
            if ( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( $sentence ) )
            {
                $sentence_lang = '';
            }
        }

        my $sentence_ref = {};
        $sentence_ref->{ sentence }         = $sentence;
        $sentence_ref->{ language }         = $sentence_lang;
        $sentence_ref->{ sentence_number }  = $sentence_num;
        $sentence_ref->{ stories_id }       = $story->{ stories_id };
        $sentence_ref->{ media_id }         = $story->{ media_id };
        $sentence_ref->{ publish_date }     = $story->{ publish_date };
        $sentence_ref->{ disable_triggers } = MediaWords::DB::story_triggers_disabled();

        push( @{ $sentence_refs }, $sentence_ref );
    }

    return $sentence_refs;
}

# update story vectors for the given story, updating story_sentences
# if no_delete is true, do not try to delete existing entries in the above table before creating new ones
# (useful for optimization if you are very sure no story vectors exist for this story).  If
# $no_dedup_sentences is true, do not perform sentence deduplication (useful if you are reprocessing a
# small set of stories)
sub update_story_sentences_and_language
{
    my ( $db, $story, $no_delete, $no_dedup_sentences, $ignore_date_range ) = @_;

    my $stories_id = $story->{ stories_id };

    $db->query( "DELETE FROM story_sentences WHERE stories_id = ?", $stories_id ) unless ( $no_delete );

    unless ( $ignore_date_range or _story_within_media_source_story_words_date_range( $db, $story ) )
    {
        say STDERR "Won't split story " .
          $stories_id . " " . "into sentences / words and determine their language because " .
          "story is *not* within media source's story words date range and 'ignore_date_range' is not set.";
        return;
    }

    my $story_text = $story->{ story_text } || MediaWords::DBI::Stories::get_text_for_word_counts( $db, $story ) || '';

    my $story_lang = MediaWords::Util::IdentifyLanguage::language_code_for_text( $story_text, '' );

    my $sentences = _get_sentences_from_story_text( $story_text, $story_lang );

    if ( !$story->{ language } || ( $story_lang ne $story->{ language } ) )
    {
        $db->query( "UPDATE stories SET language = ? WHERE stories_id = ?", $story_lang, $stories_id );
        $story->{ langauge } = $story_lang;
    }

    die "Sentences for story $stories_id are undefined." unless ( defined $sentences );

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

    my $sentence_refs = _get_story_sentence_refs( $sentences, $story );

    _insert_story_sentences( $db, $story, $sentence_refs );

    _update_ap_syndicated( $db, $story );

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
            _limit_string_length( $word, $word_length_limit );
            _limit_string_length( $stem, $word_length_limit );
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
