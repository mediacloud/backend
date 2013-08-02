#!/usr/bin/env perl

# Run through stories found for the given controversy and find all the links in each story.
# For each link, try to find whether it matches any given story.  If it doesn't, create a
# new story.  Add that story's links to the queue if it matches the pattern for the
# controversy.  Write the resulting stories and links to controversy_stories and controversy_links.

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
    my ( $controversies_id, $dedup_stories );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions(
        "controversy=s"  => \$controversies_id,
        "dedup_stories!" => \$dedup_stories,
    ) || return;

    die( "usage: $0 --controversy < controversies_id > [--dedup_stories]" ) unless ( $controversies_id );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "Unable to find controversy '$controversies_id'" );

    MediaWords::CM::Mine::mine_controversy( $db, $controversy, $dedup_stories );
}

main();
