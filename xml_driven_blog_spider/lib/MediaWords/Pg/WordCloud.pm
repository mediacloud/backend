package MediaWords::Pg::WordCloud;

# postgres plperl functions for creating word clouds

use Encode;
use File::Temp;

use MediaWords::Pg;

use strict;

# name of media tag for media sources to include in word clouds
# in the form of tag_set_name:tag_name
use constant WORD_CLOUD_MEDIA_TAG => 'word_cloud:include';

# get the id of the WORD_CLOUD_MEDIA_TAG
sub _get_word_cloud_media_tag_id {
    my ($tag_set_name, $tag_name) = split(':', WORD_CLOUD_MEDIA_TAG); 
    
    my $tag = exec_prepared("select t.tags_id from tags t, tag_sets ts where t.tag_sets_id = ts.tag_sets_id " .
                            "and t.tag = \$1 and ts.name = \$2",
                            [ 'TEXT', 'TEXT' ], [ $tag_name, $tag_set_name ])->{rows}->[0];
                            
    if (!$tag) {
        die("Unable to find WORD_CLOUD_MEDIA_TAG: '" . WORD_CLOUD_MEDIA_TAG . "'");
    }

    return $tag->{tags_id};
}

# add the story to the word cloud hash using the table
sub _add_story_to_cloud {
    my ($cloud, $table, $stories_id, $story_matches_query) = @_;
    
    my $story_words_handle = query_prepared("select cast(date_trunc('week', s.publish_date) as date) as week, s.media_id, sw.* " . 
                                            "from ${table} sw, stories s " . 
                                            "where sw.stories_id = \$1 and s.stories_id = \$1",
                                            [ 'INT' ], [ $stories_id ]);

    while (my $story_word = fetchrow($story_words_handle)) {
        $cloud->{ $story_word->{media_id} }->{ $story_word->{week} }
            ->{ $story_word->{term} }->{ $story_matches_query }->{story_count} += 1;
        $cloud->{ $story_word->{media_id} }->{ $story_word->{week} }
            ->{ $story_word->{term} }->{ $story_matches_query }->{term_count} += $story_word->{term_count};
    }

    cursor_close($story_words_handle);

}

# insert the word cloud into the table
sub _insert_terms_into_table {
    my ($table, $word_cloud) = @_;
 
    pg_log("inserting terms into $table ...");

    my $fh = File::Temp->new( UNLINK => 0 );

    while (my ($media_id, $weeks) = each(%{$word_cloud})) {
        while (my ($week, $words) = each(%{$weeks})) {
            while (my ($word, $matches) = each(%{$words})) {
                while (my ($match, $counts) = each(%{$matches})) {
                        
                    if (($counts->{term_count} > 1) || ($counts->{story_count} > 1)) {
                        $fh->print(join("\t", encode('utf8', $word), $counts->{term_count}, $counts->{story_count}, 
                                        $media_id, $week, $match) . "\n");
                    }
                }
            }
        }
    }

    $fh->close();
    
    exec_query("copy $table (term, term_count, story_count, media_id, week, matches_query) from '" . $fh->filename . "'");
    
    unlink($fh->filename);

}

# create indexes for and analyze terms table
sub _index_terms_table {
    my ($table) = @_;
    
    pg_log("indexing and analyzing $table ...");
 
    my $index_name_table = $table;
    $index_name_table =~ s/\./_/;
    
    exec_query("create index ${index_name_table}_m on ${table} (media_id, week, matches_query)");
    exec_query("create index ${index_name_table}_t on ${table} (term)");
    exec_query("analyze ${table}");
}

# query word_cloud_queries to determine whether the query has already been added
sub _query_exists {
    my ($query) = @_;

    return exec_prepared("select * from word_cloud_queries where query = \$1", [ 'TEXT' ], [ $query ])->{rows}->[0];
}

# create a world cloud table with the given name
sub _create_word_cloud_table {
    my ($table) = @_;
    
    exec_query("create table $table (term text, term_count int, story_count int, media_id int, week date, matches_query boolean)");            
}

# plperl function to create denormalized support tables for word clouds for a given query term and dates
sub add_word_cloud_query {
    my ($query) = @_;

    pg_log("create_word_cloud_query $query  ...");

    if ((length($query) > 48) || ($query =~ /[^a-z0-9_]/i)) {
        die("illegal query '$query'");
    }
    
    if (_query_exists($query)) {
        return "query '$query' already exists";
    }
    
    my $word_cloud_query = exec_prepared("insert into word_cloud_queries (query) values (\$1) returning *",
                                         [ 'TEXT' ], [ $query ])->{rows}->[0];
    
    my $schema = "word_cloud_$query";
    exec_query("create schema $schema");    
        
    _create_word_cloud_table("$schema.words");
    _create_word_cloud_table("$schema.phrases");

    pg_log("querying stories ...");
    
    my $media_tags_id = _get_word_cloud_media_tag_id();
    # can't prepare this b/c query api doesn't like parameters in to_tsquery for some reason 
    my $story_query_handle = query("select cast(date_trunc('week', s.publish_date) as date) as week, sv.stories_id, " . 
                                   "sv.vector @@ to_tsquery('english', '$query') as matches_query " .
                                   "from story_vectors sv, stories s, media_tags_map mtm " . 
                                   "where s.stories_id = sv.stories_id and " . 
                                   #"s.publish_date between DATE '2008-09-03' and DATE '2008-09-03' and " .
                                   "s.media_id = mtm.media_id and mtm.tags_id = " . $media_tags_id . " " .
                                   "order by s.publish_date, s.media_id");

    my $count = 0;
    my $prev_query;
    my ($word_cloud, $phrase_cloud) = ({}, {});
    while (my $story_query = fetchrow($story_query_handle)) {
        if (!(++$count % 100)) {
            pg_log("story $count");
        }

        if ($prev_query && (($prev_query->{week} ne $story_query->{week}) || ($prev_query->{media_id} ne $story_query->{media_id}))) {
            _insert_terms_into_table("$schema.words", $word_cloud);
            _insert_terms_into_table("$schema.phrases", $phrase_cloud);
            $word_cloud = {};
            $phrase_cloud = {};
        }

        _add_story_to_cloud($word_cloud, "story_words", $story_query->{stories_id}, $story_query->{matches_query});
        _add_story_to_cloud($phrase_cloud, "story_phrases", $story_query->{stories_id}, $story_query->{matches_query});
        
        $prev_query = $story_query;
        
    }    

    cursor_close($story_query_handle);
    
    _insert_terms_into_table("$schema.words", $word_cloud);
    _insert_terms_into_table("$schema.phrases", $phrase_cloud);
    
    _index_terms_table("$schema.words");
    _index_terms_table("$schema.phrases");

    freeplans();

    return "done";
}

1;


