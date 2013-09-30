package MediaWords::GearmanFunction::SearchStories;

#
# Run a loop running any pending jobs in query_story_searches
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh ./script/mediawords_gearman_worker.pl lib/MediaWords/GearmanFunction/SearchStories.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::GearmanFunction';

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Queries;
use MediaWords::Util::CSV;

# execute the story search, store the results as a csv in the query_story_search, and mark the query_story_search as completed
sub _execute_and_store_search
{
    my ( $db, $query_story_search ) = @_;

    my $query = MediaWords::DBI::Queries::find_query_by_id( $db, $query_story_search->{ queries_id } );

    say STDERR "searching for $query_story_search->{ pattern } in $query->{ description } ...";

    my $stories = MediaWords::DBI::Queries::search_stories( $db, $query, $query_story_search );

    my $stories_inserted = {};
    for my $story ( @{ $stories } )
    {
        next if ( $stories_inserted->{ $story->{ stories_id } } );
        $db->query(
            "insert into query_story_searches_stories_map ( query_story_searches_id, stories_id ) values ( ?, ? )",
            $query_story_search->{ query_story_searches_id },
            $story->{ stories_id }
        );
        $stories_inserted->{ $story->{ stories_id } } = 1;
    }

    $db->query( "update query_story_searches set search_completed = 't' where query_story_searches_id = ?",
        $query_story_search->{ query_story_searches_id } );

    say STDERR "done.";
}

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    $db->begin_work;

    my $query_story_searches = $db->query( "select * from query_story_searches where search_completed = 'f'" )->hashes;
    if ( @{ $query_story_searches } )
    {
        map { _execute_and_store_search( $db, $_ ) } @{ $query_story_searches };
    }

    $db->commit;

    $db->disconnect;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
