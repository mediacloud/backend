package MediaWords::GearmanFunction::CM::MineControversy;

#
# Run through stories found for the given controversy and find all the links in
# each story.
#
# For each link, try to find whether it matches any given story. If it doesn't,
# create a new story. Add that story's links to the queue if it matches the
# pattern for the controversy. Write the resulting stories and links to
# controversy_stories and controversy_links.
#
# Options:
#
# * dedup_stories - run story deduping code over existing controversy stories;
#   only necessary to rerun new dedup code
#
# * import_only - only import query_story_searches and controversy_seed_urls;
#   do not run spider cache_broken_downloads - cache broken downloads found in
#   query_story_search; speeds up spider if there are many broken downloads;
#   slows it down considerably if there are not
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/gjs_worker.pl lib/MediaWords/GearmanFunction/CM/MineControversy.pm
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

use MediaWords::CM::Mine;
use MediaWords::DB;

# Run job
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $controversies_id                = $args->{ controversies_id };
    my $import_only                     = $args->{ import_only } // 0;
    my $cache_broken_downloads          = $args->{ cache_broken_downloads } // 0;
    my $skip_outgoing_foreign_rss_links = $args->{ skip_outgoing_foreign_rss_links } // 0;

    unless ( $controversies_id )
    {
        die "'controversies_id' is not set.";
    }

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      or die( "Unable to find controversy '$controversies_id'" );

    my $options = {
        import_only                     => $import_only,
        cache_broken_downloads          => $cache_broken_downloads,
        skip_outgoing_foreign_rss_links => $skip_outgoing_foreign_rss_links
    };

    MediaWords::CM::Mine::mine_controversy( $db, $controversy, $options );

}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
