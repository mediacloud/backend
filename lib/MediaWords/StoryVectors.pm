package MediaWords::StoryVectors;

# methods to generate the story_sentences and story_sentence_words and associated aggregated tables

use strict;
use Encode;
use Encode::HanConvert;
use Perl6::Say;
use Lingua::ZH::WordSegmenter;
use Data::Dumper;

use Lingua::EN::Sentence::MediaWords;
use Lingua::ZH::MediaWords;
use MediaWords::DBI::Stories;
use MediaWords::Util::Stemmer;
use MediaWords::Util::StopWords;
use MediaWords::Util::Countries;

use Date::Format;
use Date::Parse;
use utf8;

# minimum length of words in story_sentence_words
use constant MIN_STEM_LENGTH => 3;

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
        return $db->query( "select stories_id, publish_date, media_id from stories where stories_id = ?", $story )->hash;
    }
}

# given a hash of word counts by sentence, insert the words into the db
sub _insert_story_sentence_words
{
    my ( $db, $story, $word_counts ) = @_;

    while ( my ( $sentence_num, $sentence_counts ) = each( %{ $word_counts } ) )
    {
        while ( my ( $stem, $hash ) = each( %{ $sentence_counts } ) )
        {

#print STDERR $story->{ stories_id }.$hash->{ count }.$sentence_num.encode_utf8( $stem ).encode_utf8( lc( $hash->{ word } ) ).$story->{ publish_date }.$story->{ media_id };
#print STDERR "\n";

            eval {
                $db->query(
'insert into story_sentence_words (stories_id, stem_count, sentence_number, stem, term, publish_day, media_id) '
                      . '  values ( ?,?,?,?,?,?,? )',
                    $story->{ stories_id },
                    $hash->{ count },
                    $sentence_num,
                    encode_utf8( $stem ),
                    encode_utf8( lc( $hash->{ word } ) ),
                    $story->{ publish_date },
                    $story->{ media_id }
                );

            };
            if ( $@ )
            {
                print STDERR "Error inserting into story_sentence_words\n";
                die $@;
            }
        }
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

# insert the story sentence into the db
sub _insert_story_sentence
{
    my ( $db, $story, $sentence_num, $sentence ) = @_;

    $db->query(
        "insert into story_sentences (stories_id, sentence_number, sentence, publish_date, media_id) " .
          "  values (?,?,?,?,?)",
        $story->{ stories_id },
        $sentence_num, $sentence,
        $story->{ publish_date },
        $story->{ media_id }
    );
}

# simple tokenizer
sub _tokenize
{
    my ( $s ) = @_;

    my $tokens = [];
    while ( $s->[ 0 ] =~ m~(\w[\w']*)~g )
    {
        push( @{ $tokens }, lc( $1 ) );
    }

    return $tokens;
}

#Chinese tokenizer, returns an array of Chinese words
sub _tokenize_ZH
{
    my $s         = shift;
    my $segmenter = shift;
    my $i;
    $s = encode( "utf8", $s );
    my $segs = $segmenter->seg( $s, "utf8" );
    my $tokens;
    @$tokens = split( / /, $segs );
    my $token;

    foreach $token ( @$tokens )
    {
        $token =~ s/[\W\d_\s]+//g;
    }

    for ( $i = 0 ; $i < $#$tokens ; $i++ )
    {
        if ( $tokens->[ $i ] eq "" )
        {
            splice @$tokens, $i, 1;
            $i--;
        }
    }

    #foreach $token ( @$tokens )
    #{
    #    print $token. "\n";
    #}
    return $tokens;
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

# return the number of sentences of this sentence within the same media source and calendar week.
# also adds the sentence to the story_sentence_counts table and/or increments the count in that table
# for the sentence.  Note that this is not a perfect count -- we don't try to lock this b/c it's not
# worth the performance hit, so multiple initial entries for a given sentence might be created (even
# though the order by on the select will minimize this effect).
sub count_duplicate_sentences
{
    my ( $db, $sentence, $sentence_number, $story ) = @_;

    my $dup_sentence = $db->query(
        "select * from story_sentence_counts " .
          "  where sentence_md5 = md5( ? ) and media_id = ? and publish_week = date_trunc( 'week', ?::date )" .
          "  order by story_sentence_counts_id limit 1",
        $sentence,
        $story->{ media_id },
        $story->{ publish_date }
    )->hash;

    if ( $dup_sentence )
    {
        $db->query(
            "update story_sentence_counts set sentence_count = sentence_count + 1 " . "  where story_sentence_counts_id = ?",
            $dup_sentence->{ story_sentence_counts_id }
        );
        return $dup_sentence->{ sentence_count };
    }
    else
    {
        $db->query(
            "insert into story_sentence_counts( sentence_md5, media_id, publish_week, " .
              "    first_stories_id, first_sentence_number, sentence_count ) " .
              "  values ( md5( ? ), ?, date_trunc( 'week', ?::date ), ?, ?, 1 )",
            $sentence,
            $story->{ media_id },
            $story->{ publish_date },
            $story->{ stories_id },
            $sentence_number
        );
        return 0;
    }
}

# given a story and a list of sentences, return all of the stories that are not duplicates as defined by
# count_duplicate_sentences()
sub dedup_sentences
{
    my ( $db, $story, $sentences ) = @_;

    my $deduped_sentences = [];
    for my $sentence ( @{ $sentences } )
    {
        my $num_dups = count_duplicate_sentences( $db, $sentence, scalar( @{ $deduped_sentences } ), $story );

        if ( $num_dups == 0 )
        {
            push( @{ $deduped_sentences }, $sentence );
        }
        else
        {

            # print STDERR "ignoring duplicate sentence: '$sentence'\n";
        }
    }

    if ( @{ $sentences } && !@{ $deduped_sentences } )
    {

        # FIXME - should do something here to find out if this is just a duplicate story and
        # try to merge the given story with the existing one
        print STDERR "all sentences deduped for stories_id $story->{ stories_id }\n";
    }

    return $deduped_sentences;
}

# update story vectors for the given story, updating story_sentences and story_sentence_words
# if no_delete is true, do not try to delete existing entries in the above table before creating new ones (useful for optimization
# if you are very sure no story vectors exist for this story).
sub update_story_sentence_words
{
    my ( $db, $story_ref, $no_delete ) = @_;
    my $sentence_word_counts;
    my $story = _get_story( $db, $story_ref );

    unless ( $no_delete )
    {
        $db->query( "delete from story_sentence_words where stories_id = ?",        $story->{ stories_id } );
        $db->query( "delete from story_sentences where stories_id = ?",             $story->{ stories_id } );
        $db->query( "delete from story_sentence_counts where first_stories_id = ?", $story->{ stories_id } );
    }

    my $story_text = MediaWords::DBI::Stories::get_text_for_word_counts( $db, $story );

    my $enable_chinese_support = MediaWords::Util::Config::get_config->{ mediawords }->{ enable_chinese_language_support }
      || 'no';

    my $is_Chinese = 0;

    if ( $enable_chinese_support eq 'yes' && Lingua::ZH::MediaWords::text_is_Chinese( $story_text ) )
    {
        $is_Chinese = 1;
    }

    #if the text is in Chinese
    if ( $is_Chinese )
    {

        my $base_dir;

        BEGIN
        {
            use File::Basename ();
            use Cwd            ();

            my $relative_path = '../..';    # Path to base of project relative to the current file
            $base_dir = Cwd::realpath( File::Basename::dirname( __FILE__ ) . '/' . $relative_path );
        }

        my %par = ();
        $par{ "dic_encoding" } = "utf8";
        $par{ "dic" }          = "$base_dir/lib/Lingua/ZH/dict.txt";
        my $segmenter = Lingua::ZH::WordSegmenter->new( %par );

        #convert traditional characters into simplified characters
        $story_text = trad_to_simp( $story_text );

        my $sentences = Lingua::ZH::MediaWords::get_sentences( $story_text );
        $sentences = dedup_sentences( $db, $story_ref, $sentences );
        my $stop_words = MediaWords::Util::StopWords::get_Chinese_stopwords();
        my $count      = 0;

        for ( my $sentence_num = 0 ; $sentence_num < $#$sentences ; $sentence_num++ )
        {
            my $words = _tokenize_ZH( $sentences->[ $sentence_num ], $segmenter );

            #print $sentences[$sentence_num]."\n\n----------\n";
            #print join "\n\n", @words;
            for ( my $word_num = 0 ; $word_num < $#$words ; $word_num++ )
            {
                my $word = ( $words->[ $word_num ] );

                if ( ( !$$stop_words{ $word } ) )
                {
                    $sentence_word_counts->{ $sentence_num }->{ $word }->{ word } ||= $word;
                    $sentence_word_counts->{ $sentence_num }->{ $word }->{ count }++;
                }
            }
            _insert_story_sentence( $db, $story, $sentence_num, $sentences->[ $sentence_num ] );
        }

    }

    #if the text is in English
    else
    {
        my $stop_stems = MediaWords::Util::StopWords::get_tiny_stop_stem_lookup();
        my $stemmer    = MediaWords::Util::Stemmer->new;
        my $sentences  = Lingua::EN::Sentence::MediaWords::get_sentences( $story_text ) || return;
        $sentences = dedup_sentences( $db, $story_ref, $sentences );

        for ( my $sentence_num = 0 ; $sentence_num < @{ $sentences } ; $sentence_num++ )
        {
            my $words = _tokenize( [ $sentences->[ $sentence_num ] ] );
            my $stems = $stemmer->stem( @{ $words } );

            for ( my $word_num = 0 ; $word_num < @{ $words } ; $word_num++ )
            {
                my ( $word, $stem ) = ( $words->[ $word_num ], $stems->[ $word_num ] );

                limit_string_length( $word, 256 );
                limit_string_length( $stem, 256 );

                if ( _valid_stem( $stem, $word, $stop_stems ) )
                {
                    $sentence_word_counts->{ $sentence_num }->{ $stem }->{ word } ||= $word;
                    $sentence_word_counts->{ $sentence_num }->{ $stem }->{ count }++;
                }
            }

            _insert_story_sentence( $db, $story, $sentence_num, $sentences->[ $sentence_num ] );
        }
    }

    _insert_story_sentence_words( $db, $story, $sentence_word_counts );

    #testing print
    q{while ( my ($key, $value) = each(%$sentence_word_counts) ) {
		 	print "level 1:  $key\n";
			while ( my ($key, $value1) = each(%$value) ) {
       				 print "*level 2:  $key\n";
				while ( my ($key, $value2) = each(%$value1) ) {
		   				 print "**level 3:  $key => $value2\n";
	   			 }
   			}
	 }};
}

# fill the story_sentence_words table with all stories in ssw_queue
sub fill_story_sentence_words
{
    my ( $db ) = @_;

    my $block_size = 1;

    my $count = 0;
    while ( my $stories = $db->query( "select * from ssw_queue order by stories_id limit $block_size" )->hashes )
    {
        if ( !@{ $stories } )
        {
            last;
        }

        for my $story ( @{ $stories } )
        {
            say STDERR "story [ $story->{ stories_id } ] " . ++$count . " ...";

            update_story_sentence_words( $db, $story, 0 );

            $db->query( "delete from ssw_queue where stories_id = ?", $story->{ stories_id } );
        }
        $db->commit();
    }
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

    return "and $d and $m";
}

# update the top_500_weekly_words table with the 500 most common stop worded stems for each media_sets_id each week
sub _update_top_500_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: top_500_weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query(
        "delete from top_500_weekly_words where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses" );
    $db->query(
        "delete from total_top_500_weekly_words where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses"
    );

    # Note in postgresql [:alpha:] doesn't include international characters.
    # [^[:digit:][:punct:][:cntrl:][:space:]] is the closest equivalent to [:alpha:] to include international characters
    $db->query(
        "insert into top_500_weekly_words (media_sets_id, term, stem, stem_count, publish_week, dashboard_topics_id) " .
          "  select media_sets_id, regexp_replace( term, E'''s?\\\\Z', '' ), " .
          "      stem, stem_count, publish_week, dashboard_topics_id " . "    from ( " .
          "      select media_sets_id, term, stem, stem_count, publish_week, dashboard_topics_id, " .
          "          rank() over ( partition by media_sets_id, dashboard_topics_id order by stem_count desc ) as stem_rank  "
          . "      from weekly_words "
          . "      where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses "
          . "        and not is_stop_stem( 'long', stem ) and stem ~ '[^[:digit:][:punct:][:cntrl:][:space:]]' ) q "
          . "    where stem_rank < 500 "
          . "    order by stem_rank asc " );

    $db->query( "insert into total_top_500_weekly_words (media_sets_id, publish_week, total_count, dashboard_topics_id) " .
          "  select media_sets_id, publish_week, sum( stem_count ), dashboard_topics_id from top_500_weekly_words " .
          "    where publish_week = date_trunc( 'week', '$sql_date'::date ) $update_clauses " .
          "    group by media_sets_id, publish_week, dashboard_topics_id" );
}

# update the given table for the given date and interval
sub _update_daily_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: daily_words $sql_date";

    my $dashboard_topic_clause = _get_dashboard_topic_clause( $dashboard_topics_id );
    my $media_set_clause       = _get_media_set_clause( $media_sets_id );
    my $update_clauses         = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query( "delete from daily_words where publish_day = date_trunc( 'day', '${ sql_date }'::date ) $update_clauses" );
    $db->query(
        "delete from total_daily_words where publish_day = date_trunc( 'day', '${ sql_date }'::date ) $update_clauses" );

    if ( !$dashboard_topics_id )
    {
        $db->query( "insert into daily_words (media_sets_id, term, stem, stem_count, publish_day, dashboard_topics_id) " .
              "          select media_sets_id, term, stem, sum_stem_counts, publish_day, null from " .
              "               (select  *, rank() over (w order by stem_count_sum desc, term desc) as term_rank, " .
              "                sum(stem_count_sum) over w as sum_stem_counts  from " .
              "                    ( select media_sets_id, term, stem, sum(stem_count) as stem_count_sum, " .
              "                      min(publish_day) as publish_day, null " .
              "                      from story_sentence_words ssw, media_sets_media_map msmm  " .
              "                      where ssw.publish_day = '${sql_date}'::date and " .
              "                      ssw.media_id = msmm.media_id and  $media_set_clause " .
              "                      group by msmm.media_sets_id, ssw.stem, ssw.term " .
              "                        ) as foo  " .
              "                WINDOW w  as (partition by media_sets_id, stem, publish_day ) " .
              "	               )  q                                                         " .
              "              where term_rank = 1 and sum_stem_counts > 1 " );
    }

    my $dashboard_topics = $db->query(
        "select * from dashboard_topics " . "  where $dashboard_topic_clause and ?::date between start_date and end_date",
        $sql_date )->hashes;

    for my $dashboard_topic ( @{ $dashboard_topics } )
    {
        my $query_2 =
          "    insert into daily_words (media_sets_id, term, stem, stem_count, publish_day, dashboard_topics_id) " .
          "          select media_sets_id, term, stem, sum_stem_counts, publish_day, dashboard_topics_id from " .
          "               (select  *, rank() over (w order by stem_count_sum desc, term desc) as term_rank, " .
          "                sum(stem_count_sum) over w as sum_stem_counts  from " .
          " ( select media_sets_id, ssw.term, ssw.stem, sum(ssw.stem_count) stem_count_sum,    " .
          "  min(ssw.publish_day) as publish_day, ?::integer as dashboard_topics_id  from " .
          "     story_sentence_words ssw,                                                          " .
          "( select media_sets_id, stories_id, sentence_number from story_sentence_words sswq, media_sets_media_map msmm " .
          " where                                                           " .
          " sswq.media_id = msmm.media_id and sswq.stem = ? and sswq.publish_day = ? and " .
          " $media_set_clause  group by msmm.media_sets_id, stories_id, sentence_number " .
          " ) as ssw_sentences_for_query  " . " where ssw.stories_id=ssw_sentences_for_query.stories_id and " .
          " ssw.sentence_number=ssw_sentences_for_query.sentence_number " . " group by media_sets_id, ssw.stem, term " .
          "                        ) as foo  " .
          "                WINDOW w  as (partition by media_sets_id, stem, publish_day ) " .
          "	               )  q                                                         " .
          "             where term_rank = 1 and sum_stem_counts > 1 ";

        # doing these one by one is the only way I could get the postgres planner to create
        # a sane plan
        $db->query( $query_2, $dashboard_topic->{ dashboard_topics_id }, $dashboard_topic->{ query }, $sql_date );
    }

    $db->query( "insert into total_daily_words (media_sets_id, publish_day, total_count, dashboard_topics_id) " .
          " select media_sets_id, publish_day, sum(stem_count), dashboard_topics_id " . " from daily_words " .
          " where publish_day = '${sql_date}'::date $update_clauses " .
          " group by media_sets_id, publish_day, dashboard_topics_id " );

    return 1;
}

# update the given table for the given date and interval
sub _update_daily_country_counts
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: _update_daily_country_counts $sql_date";

    my $dashboard_topic_clause = _get_dashboard_topic_clause( $dashboard_topics_id );
    my $media_set_clause       = _get_media_set_clause( $media_sets_id );
    my $update_clauses         = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    say STDERR
      "delete from daily_country_counts where publish_day = date_trunc( 'day', '${ sql_date }'::date ) $update_clauses";

    $db->query(
        "delete from daily_country_counts where publish_day = date_trunc( 'day', '${ sql_date }'::date ) $update_clauses" );

    my $result =
      $db->query( " SELECT count(*) FROM story_sentence_words ssw where publish_day = '${sql_date}'::DATE limit 1" );
    die unless $result;
    my $word_count_for_date = join '', $result->flat();

    if ( $word_count_for_date == 0 )
    {

        say STDERR "skipping country counts for date '$sql_date' for which there is no content";
        return 1;
    }

    #my @all_countries = map { lc } Locale::Country::all_country_names;
    my $all_countries = MediaWords::Util::Countries::get_countries_for_counts();

    if ( !$dashboard_topics_id )
    {

        #say STDERR Dumper($all_countries);
        #exit;

        for my $country ( @$all_countries )
        {

            #say STDERR $country;
            my ( $country_term1, $country_term2, $country_term3 ) =
              MediaWords::Util::Countries::get_stemmed_country_terms( $country );

            my $country_data_base_value = MediaWords::Util::Countries::get_country_data_base_value( $country );

            say STDERR "_update_daily_country_counts  $sql_date '$country_data_base_value'";
            my $query =
              "INSERT INTO   daily_country_counts ( media_sets_id, publish_day, country, country_count ) " .
              "SELECT media_sets_id, publish_day, ?, COUNT(*) FROM              " .
              "(SELECT  ssw.stories_id, ssw.sentence_number, msmm.media_sets_id, ssw.publish_day " .
              " FROM story_sentence_words ssw, story_sentence_words ssw2, story_sentence_words ssw3, " .
              " media_sets_media_map msmm,  story_sentences ss " .
              "   WHERE    ss.stories_id =ssw.stories_id AND ss.sentence_number=ssw.sentence_number AND " .
              "    ssw.media_id = msmm.media_id AND $media_set_clause AND ssw.publish_day = '${sql_date}'::DATE " .
              "    AND ssw.stem =? AND ssw2.stem = ? AND ssw3.stem = ? AND ssw2.stories_id =ssw.stories_id AND " .
              " ssw2.sentence_number=ssw.sentence_number AND ssw3.stories_id =ssw.stories_id AND " .
              "ssw3.sentence_number=ssw.sentence_number " .
              "         GROUP BY ssw.stories_id, ssw.sentence_number, msmm.media_sets_id, ssw.publish_day " .
              "        ) AS foo                    " . "GROUP BY media_sets_id, publish_day";

            #say STDERR $query;
            #say STDERR Dumper ([($country_data_base_value, $country_term1, $country_term2, $country_term3)] );

            $db->query( $query, $country_data_base_value, $country_term1, $country_term2, $country_term3 );
        }
    }

    my $dashboard_topics = $db->query(
        "select * from dashboard_topics " . "  where $dashboard_topic_clause and ?::date between start_date and end_date",
        $sql_date )->hashes;

    for my $dashboard_topic ( @{ $dashboard_topics } )
    {
        for my $country ( @$all_countries )
        {

            #say STDERR $country;

            my $stemmer = MediaWords::Util::Stemmer->new;

            my @country_split = split ' ', $country;

            #next unless scalar(@country_split) > 2;
            #say $country;

            #say Dumper (@country_split);
            #say Dumper ([$stemmer->stem( @country_split )]);

            #$DB::single = 2;
            my ( $country_term1, $country_term2, $country_term3 ) = @{ $stemmer->stem( @country_split ) };

            #say STDERR Dumper([($country_term1, $country_term2)]);

            #exit;
            if ( !defined( $country_term2 ) )
            {
                $country_term2 = $country_term1;
            }

            if ( !defined( $country_term3 ) )
            {
                $country_term3 = $country_term1;
            }

            my $country_data_base_value =
              ( $country_term1 eq $country_term2 ) ? $country_term1 : "$country_term1 $country_term2";
            if ( $country_term3 ne $country_term1 )
            {
                $country_data_base_value .= " $country_term3";
            }
            my $query_2 =
"INSERT INTO   daily_country_counts ( media_sets_id, publish_day, country, country_count, dashboard_topics_id ) "
              . "SELECT media_sets_id, publish_day, ?, COUNT(*), ?::integer as dashboard_topics_id  FROM      "
              . "(SELECT  ssw.stories_id, ssw.sentence_number, msmm.media_sets_id, ssw.publish_day "
              . " FROM story_sentence_words ssw, story_sentence_words ssw2, story_sentence_words ssw3, "
              . " media_sets_media_map msmm,  story_sentences ss, "
              . " story_sentence_words sswt  "
              . "   WHERE    ss.stories_id =ssw.stories_id AND ss.sentence_number=ssw.sentence_number AND "
              . "sswt.stories_id=ssw.stories_id AND     "
              . " sswt.sentence_number=ssw.sentence_number AND sswt.stem =? AND "
              . "    ssw.media_id = msmm.media_id AND $media_set_clause AND ssw.publish_day = '${sql_date}'::DATE "
              . "    AND ssw.stem =? AND ssw2.stem = ? AND ssw3.stem = ? AND ssw2.stories_id =ssw.stories_id AND "
              . " ssw2.sentence_number=ssw.sentence_number AND ssw3.stories_id =ssw.stories_id AND "
              . "ssw3.sentence_number=ssw.sentence_number "
              . "         GROUP BY ssw.stories_id, ssw.sentence_number, msmm.media_sets_id, ssw.publish_day "
              . "        ) AS foo                  GROUP BY media_sets_id, publish_day";

            # doing these one by one is the only way I could get the postgres planner to create
            # a sane plan

#say STDERR "Query:\n" . "$query_2";
#say STDERR " $country_data_base_value, $dashboard_topic->{ dashboard_topics_id }, $dashboard_topic->{ query }, $sql_date, $country_term1, $country_term2, $country_term3";

            say STDERR "_update_daily_country_counts  $sql_date  '$dashboard_topic->{ query }' '$country_data_base_value'";

            $db->query(
                $query_2, $country_data_base_value,
                $dashboard_topic->{ dashboard_topics_id },
                $dashboard_topic->{ query },
                $country_term1, $country_term2, $country_term3
            );
        }

    }

    return 1;
}

# update the given table for the given date and interval
sub _update_weekly_words
{
    my ( $db, $sql_date, $dashboard_topics_id, $media_sets_id ) = @_;

    say STDERR "aggregate: weekly_words $sql_date";

    my $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );

    $db->query(
        "delete from weekly_words where publish_week = date_trunc( 'week', '${ sql_date }'::date ) $update_clauses " );

    $db->query( "insert into weekly_words (media_sets_id, term, stem, stem_count, publish_week, dashboard_topics_id) " .
          "  select media_sets_id, term, stem, sum_stem_counts, publish_week, dashboard_topics_id from      " .
          "   (select  *, rank() over (w order by stem_count_sum desc, term desc) as term_rank, " .
          "     sum(stem_count_sum) over w as sum_stem_counts  from " .
          "(  select media_sets_id, term, stem, sum(stem_count) as stem_count_sum, " .
          "date_trunc('week', min(publish_day)) as publish_week, dashboard_topics_id from daily_words " .
          "    where publish_day between date_trunc('week', '${sql_date}'::date) " .
          "        and date_trunc( 'week', '${sql_date}'::date )  + interval '6 days' $update_clauses " .
          "    group by media_sets_id, stem, term, dashboard_topics_id ) as foo" .
          " WINDOW w  as (partition by media_sets_id, stem, publish_week,  dashboard_topics_id  ) " .
          "	               )  q                                                         " .
          "              where term_rank = 1 and sum_stem_counts > 1 " );

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
        $update_clauses = "and dashboard_topics_id is null";
    }
    else {
        $update_clauses = _get_update_clauses( $dashboard_topics_id, $media_sets_id );
    }

    return $db->query( "select 1 as c from daily_words " .
          "  where publish_day = date_trunc( 'day', date '$sql_date' ) $update_clauses limit 1" )->hash;
}

# add one day to the date in sql format
# use a postgres query to make sure we're doing the same thing as postgres, including dst
sub _increment_day
{
    my ( $date ) = @_;

    my $new_date = Date::Format::time2str( "%Y-%m-%d", Date::Parse::str2time( $date ) + 100000 );
}

# update daily_words, weekly_words, and top_500_weekly_words tables for all included dates
# for which daily_words data does not already exist
#
# if dashbaord_topics_id or media_sets_id are specified, only update for the given
# dashboard_topic or media_set
sub update_aggregate_words
{
    my ( $db, $start_date, $end_date, $force, $dashboard_topics_id, $media_sets_id ) = @_;

    $start_date ||= '2008-06-01';
    $end_date ||= Date::Format::time2str( "%Y-%m-%d", time - 86400 );

    my $days = 0;
    for ( my $date = $start_date ; $date le $end_date ; $date = _increment_day( $date ) )
    {
        say STDERR "update_aggregate_words: $date ($end_date) $days";

        if ( $force || !_aggregate_data_exists_for_date( $db, $date, $dashboard_topics_id, $media_sets_id ) )
        {
            _update_daily_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            _update_daily_country_counts( $db, $date, $dashboard_topics_id, $media_sets_id );

            # update weeklies either if we are at the end of a week
            if ( ( $date eq $end_date ) || !( localtime( Date::Parse::str2time( $date ) ) )[ 6 ] )
            {
                _update_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );
                _update_top_500_weekly_words( $db, $date, $dashboard_topics_id, $media_sets_id );
            }
        }

        $db->commit();

        $days++;
    }

    $db->commit;
}

1;
