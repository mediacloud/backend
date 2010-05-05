package MediaWords::Pg::StoryVectors;

# update the story vectors of any download texts that have been extracted since they were last vectored 
# for now, do this for a single media_id while we catch up with the archive

use strict;

use Date::Format;
use Date::Parse;
use DBIx::Simple;
use Encode;
use File::Temp;
use HTML::Strip;
use List::Util;
use Lingua::EN::Sentence::MediaWords;
use Lingua::Stem;
use Math::Combinatorics;
use Search::FreeText::LexicalAnalysis::Tokenize;
use Time::Local;

use MediaWords::DBI::Stories;
use MediaWords::Pg;
use MediaWords::Util::StopWords;

# minimum length of words in story_words
use constant MIN_WORD_LENGTH => 3;

# if story is a ref, return itself, otherwise treat it as a stories_id and query for the story ref
sub _get_story
{
    my ($story) = @_;
    
    if (ref($story)) {
        return $story;
    }
        
    my $stories_id = $story;
    $story = exec_prepared( "select stories_id, publish_date, media_id from stories where stories_id = \$1",
                            [ 'INT' ], [ $stories_id ] )->{rows}->[0];
                            
    return $story;
}

# get the text for the given story by concatenating all of the download_texts for the story
sub _get_story_text 
{
    my ($stories_id) = @_;
    
    my $download_texts = exec_prepared("select dt.download_text from downloads d, download_texts dt " .
                                        "  where dt.downloads_id = d.downloads_id and " .
                                        "    d.stories_id = \$1 order by d.downloads_id", 
                                        [ 'INT' ], [ $stories_id ])->{rows};
    return join( ". ", map { $_->{download_text} } @{$download_texts} );

}

# given a hash of word counts by sentence, insert the words into the db using sql COPY for performance
sub _insert_story_sentence_words 
{
    my ($story, $word_counts) = @_;
    
    #pg_log("write sentences\n");
    my $fh = File::Temp->new( UNLINK => 0 );
    
    while ( my ($sentence_num, $sentence_counts) = each(%{$word_counts}) )
    {
        while ( my ($stem, $hash) = each(%{$sentence_counts}) ) 
        {
            $fh->print($story->{stories_id}, "\t", $hash->{count}, "\t", $sentence_num, "\t", 
                                   decode('utf8', $stem), "\t", decode('utf8', lc($hash->{word})), "\t",
                                   $story->{publish_date}, "\t", $story->{media_id}, "\n");
        }
    }
    
    $fh->close();
    
    exec_query("copy story_sentence_words (stories_id, stem_count, sentence_number, stem, term, publish_date, media_id) " . 
               "  from '" . $fh->filename . "'");
    
    unlink($fh->filename);
}

# given a hash of word counts, insert the words into the db using sql COPY for performance
sub _insert_story_words 
{
    my ($story, $word_counts) = @_;
    
    #pg_log("write sentences\n");
    my $fh = File::Temp->new( UNLINK => 0 );
    
    while ( my ($stem, $hash) = each(%{$word_counts}) ) 
    {
        $fh->print($story->{stories_id}, "\t", $hash->{count}, "\t",
                               decode('utf8', $stem), "\t", decode('utf8', lc($hash->{word})), "\t",
                               $story->{publish_date}, "\t", $story->{media_id}, "\n");
    }
    
    $fh->close();
    
    exec_query("copy story_words (stories_id, stem_count, stem, term, publish_date, media_id) " . 
               "  from '" . $fh->filename . "'");
    
    unlink($fh->filename);
}

# return 1 if the word passes various tests
sub _valid_word 
{
    my ($stem, $word, $stop_stems) = @_;

    return ( $stem && 
            ( length($stem) >= MIN_WORD_LENGTH ) && 
            ( !$stop_stems->{ $stem } ) && 
            ( $word !~ /[^[:print:]]/ ) );
}

# insert the story sentence into the db
sub _insert_story_sentence 
{
    my ($story, $sentence_num, $sentence) = @_;
    
    exec_prepared("insert into story_sentences (stories_id, sentence_number, sentence, publish_date, media_id) " . 
              "  values (\$1, \$2, \$3, \$4, \$5)",
              [ 'INT', 'INT', 'TEXT', 'DATE', 'INT' ], 
              [ $story->{stories_id}, $sentence_num, $sentence, $story->{publish_date}, $story->{media_id} ] );
}

# break the text into sentences and words and index words by sentence and word
sub update_story_sentence_words {
    my ($story_ref, $no_delete) = @_;
    
    my $story = _get_story($story_ref);

    if (!$no_delete) {
        exec_prepared("delete from story_sentence_words where stories_id = \$1", [ 'INT' ], [ $story->{stories_id} ]);
        exec_prepared("delete from story_sentences where stories_id = \$1", [ 'INT' ], [ $story->{stories_id} ]);
        exec_prepared("delete from story_words where stories_id = \$1", [ 'INT' ], [ $story->{stories_id} ]);
    }

    my $story_text = _get_story_text($story->{stories_id});

    my $sentences = Lingua::EN::Sentence::MediaWords::get_sentences($story_text) || return;    
    my $stop_stems = MediaWords::Util::StopWords::get_tiny_stop_stem_lookup();
    my $tokenizer = new Search::FreeText::LexicalAnalysis::Tokenize();
    my $stemmer = Lingua::Stem->new;
    $stemmer->stem_caching({ -level => 2 });
        
    my ( $sentence_word_counts, $story_word_counts );
    for (my $sentence_num = 0; $sentence_num < @{$sentences}; $sentence_num++)
    {
        my $words = $tokenizer->process([ $sentences->[ $sentence_num ] ]);
    
        my $stems = $stemmer->stem( @{$words} );

        for ( my $word_num = 0; $word_num < @{$stems}; $word_num++ ) 
        {
            if ( _valid_word( $stems->[$word_num], $words->[$word_num], $stop_stems ) )
            {
                $sentence_word_counts->{ $sentence_num }->{ $stems->[$word_num] }->{ word } ||= $words->[ $word_num ];
                $sentence_word_counts->{ $sentence_num }->{ $stems->[$word_num] }->{ count }++;

                $story_word_counts->{ $stems->[$word_num] }->{ word } ||= $words->[ $word_num ];
                $story_word_counts->{ $stems->[$word_num] }->{ count }++;
            }
        }

        _insert_story_sentence( $story, $sentence_num, $sentences->[ $sentence_num ] );
    }

    _insert_story_sentence_words( $story, $sentence_word_counts );
    _insert_story_words( $story, $story_word_counts ); 
}

# fill the story_sentence_words table with all stories in ssw_queue
sub fill_story_sentence_words 
{

    my $block_size = 10000;

    my $sth = query("select * from ssw_queue order by stories_id limit $block_size");

    my $last_sid;
    my $count = 0;
    while (my $story = fetchrow($sth)) 
    {
        pg_log("story [$story->{stories_id}] " . ++$count . " ...");

        update_story_sentence_words($story, 0);
        
        $last_sid = $story->{stories_id};
    }    
    
    if ($last_sid)
    {
        exec_prepared("delete from ssw_queue where stories_id <= \$1", [ 'INT' ], [ $last_sid ]);    
    }
    
    cursor_close($sth);
        
    return 'done';
}

# update the given table for the given date and interval
sub _update_aggregate_words_date
{
    my ( $table, $interval, $date ) = @_;
    
    my $media_field = ( $table =~ /media/ ) ? 'media_id,' : '';
    my $sql_date = time2str('%Y-%m-%d', $date);
    
    my $table_analyzed = exec_query("select 1 from ${table} limit 1")->{ rows };
    
    my $date_exists = exec_query("select 1 from ${table} " . 
                                 "  where publish_${interval} = date_trunc('${interval}', date '${sql_date}') " .
                                 "  limit 1" )->{ rows }->[ 0 ];
    if ($date_exists) 
    {
        pg_log("date exists: $table $interval $sql_date");
        return 0;
    }
    
    pg_log("aggregate: $table $interval $sql_date");    
    
    my $query = "insert into ${table} (${media_field} term, stem, stem_count, publish_${interval}) " . 
                "  select ${media_field} max(term), stem, sum(stem_count), date_trunc('${interval}', min(publish_date)) " .
                "    from story_words " . 
                "    where publish_date >= date '${sql_date}' and " . 
                "      publish_date < ( date '${sql_date}' + interval '1 ${interval}' ) " .
                "    group by ${media_field} stem " .
                "    having sum(stem_count) > 1";
                
    #pg_log($query);
    
    exec_query($query);
    
    if ( !$table_analyzed )
    {
        exec_query("analyze table ${table}");
    }
    
    pg_log("done");

    return 1;
}

# update a specific aggregate words table 
sub _update_aggregate_words_table
{
    my ( $table, $interval ) = @_;
    
    my $interval_length = ( $interval eq 'day' ) ? ( 1 * 86400 ) : ( 7 * 86400 );
    
    my $sql_date = exec_query( "select date_trunc('${interval}', date '2008-05-01') as start_date" )
        ->{ rows }->[ 0 ]->{ start_date }; 
        
    $sql_date =~ /([0-9]*)-([0-9]*)-([0-9]*)/;
    my $date = timelocal(0, 0, 0, $3, $2 - 1, $1 - 1900); 
    my $end_date = time() - $interval_length;
    while ( $date < $end_date )
    {
        _update_aggregate_words_date( $table, $interval, $date );
        $date += $interval_length;
    }
}

# update (daily|weekly)_(media|mc)_words tables
sub update_aggregate_words
{
    _update_aggregate_words_table('daily_media_words', 'day');
    _update_aggregate_words_table('weekly_media_words', 'week');
    _update_aggregate_words_table('daily_mc_words', 'day');
    _update_aggregate_words_table('weekly_mc_words', 'week');
}

# does the stem match a stem in the stop stem list?
# size should be 'tiny' (150), 'short' (~1k), or 'long' (~4k)
sub is_stop_stem
{
    my ( $size, $stem ) = @_;
    
    my $stop_stem_list;
    
    if ( $size eq 'long' ) 
    {
        $stop_stem_list = MediaWords::Util::StopWords::get_long_stop_stem_lookup();
    }
    elsif ( $size eq 'short' ) {
        $stop_stem_list = MediaWords::Util::StopWords::get_short_stop_stem_lookup();
    }
    elsif ( $size eq 'tiny' ) {
        $stop_stem_list = MediaWords::Util::StopWords::get_tiny_stop_stem_lookup();
    }
    else {
        pg_log("unknown stop list size: $size");
        return 'f';
    }

    if ( $stop_stem_list->{ lc( $stem ) } )
    {
        return 't';
    }
    else {
        return 'f';
    }
}

1;