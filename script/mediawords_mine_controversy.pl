#!/usr/bin/env perl

# Run through stories found for the given controversy and find all the links in each story.
# For each link, try to find whether it matches any given story.  If it doesn't, create a
# new story.  Add that story's links to the queue if it matches the pattern for the
# controversy.  Write the resulting stories and links to controversy_stories and controversy_links.
#
# options:
# dedup_stories - run story deduping code over existing controversy stories; only necessary to rerun
#  new dedup code
# import_only - only import query_story_searches and controversy_seed_urls; do not run spider
# cache_broken_downloads - cache broken downloads found in query_story_search; speeds up
#  spider if there are many broken downloads; slows it down considerably if there are not

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CM::Mine;
use MediaWords::DB;

sub main
{
    my ( $controversies_id, $dedup_stories, $import_only, $cache_broken_downloads );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions(
        "controversy=s"           => \$controversies_id,
        "dedup_stories!"          => \$dedup_stories,
        "import_only!"            => \$import_only,
        "cache_broken_downloads!" => \$cache_broken_downloads
    ) || return;

    die( "usage: $0 --controversy < controversies_id > [ --dedup_stories ] [ --import_only ] [ --cache_broken_downloads ]" )
      unless ( $controversies_id );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "Unable to find controversy '$controversies_id'" );

    my $options = {
        dedup_stories          => $dedup_stories,
        import_only            => $import_only,
        cache_broken_downloads => $cache_broken_downloads
    };

    MediaWords::CM::Mine::mine_controversy( $db, $controversy, $options );
}

main();
