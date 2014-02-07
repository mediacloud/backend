package MediaWords::GearmanFunction::SearchStories;

#
# Run a loop running any pending jobs in query_story_searches
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/SearchStories.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::GearmanFunction';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/gjs_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Queries;
use MediaWords::Util::CSV;

# Having a global database object should be safe because
# Gearman::JobScheduler's workers don't support fork()s anymore
my $db = undef;

# execute the story search, store the results as a csv in the
# query_story_search, and mark the query_story_search as completed
sub run($;$)
{
    my ( $self, $args ) = @_;

    unless ( $db )
    {
        # Postpone connecting to the database so that compile test doesn't do that
        $db = MediaWords::DB::connect_to_db();
    }

    my $query_story_searches_id = $args->{ query_story_searches_id };
    unless ( defined $query_story_searches_id )
    {
        die "'query_story_searches_id' is undefined.";
    }

    $db->begin_work;

    my $query_story_search = $db->find_by_id( 'query_story_searches', $query_story_searches_id );
    unless ( $query_story_search->{ query_story_searches_id } )
    {
        die "Story search query with ID $query_story_searches_id was not found.";
    }

    my $query = MediaWords::DBI::Queries::find_query_by_id( $db, $query_story_search->{ queries_id } );
    unless ( $query->{ queries_id } )
    {
        die "Query with ID " . $query_story_search->{ queries_id } .
          " for story search query " . $query_story_search->{ query_story_searches_id } . " was not found.";
    }

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

    $db->commit;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
