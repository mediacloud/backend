#!/usr/bin/env perl

# run a loop running any pending jobs in query_story_searches

# usage: mediawords_search_stories.pl

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::DBI::Queries;
use MediaWords::Util::CSV;

# execute the story search, store the results as a csv in the query_story_search, and mark the query_story_search as completed
sub execute_and_store_search
{
    my ( $db, $query_story_search ) = @_;
    
    my $query = MediaWords::DBI::Queries::find_query_by_id( $db, $query_story_search->{ queries_id } );

    my $stories = MediaWords::DBI::Queries::search_stories( $db, $query, $query_story_search );
    
    # my $fields = [ qw(stories_id url title publish_date media_id media_name media_url media_set_name story_text) ];
    # 
    # my $csv_string = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $stories_with_text, $fields );
    # 
    # $db->query( 
    #     "update query_story_searches set search_completed = 't', csv_text = ? where query_story_searches_id = ?", 
    #     $csv_string, $query_story_search->{ query_story_searches_id } );

    for my $story ( @{ $stories } )
    {
        $db->query( 
            "insert into query_story_searches_stories_map ( query_story_searches_id, stories_id ) values ( ?, ? )",
            $query_story_search->{ query_story_searches_id }, $story->{ stories_id } );
    }

    $db->query( 
        "update query_story_searches set search_completed = 't' where query_story_searches_id = ?", 
        $query_story_search->{ query_story_searches_id } );
}

sub main 
{
    while ( 1 )
    {
        my $db = MediaWords::DB::connect_to_db;
        
        $db->begin_work;
        my $query_story_searches = $db->query( "select * from query_story_searches where search_completed = 'f'" )->hashes;
        if ( @{ $query_story_searches } )
        {
            map { execute_and_store_search( $db, $_ ) } @{ $query_story_searches };
        }
        else {
            sleep 60;
        }
        $db->commit;
    }
    
}

main();