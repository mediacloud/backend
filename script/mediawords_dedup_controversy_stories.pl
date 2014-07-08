#!/usr/bin/env perl

# dedup stories in a given controversy.  should only have to be run on a controversy if the deduping
# code in CM::Mine has changed.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CM::Mine;
use MediaWords::DB;
use MediaWords::CM;

sub main
{
    my ( $controversy_opt );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions( "controversy=s" => \$controversy_opt, ) || return;

    die( "usage: $0 --controversy < controversy id or pattern >" ) unless ( $controversy_opt );

    my $db = MediaWords::DB::connect_to_db;

    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );

    for my $controversy ( @{ $controversies } )
    {
        $db->disconnect;
        $db = MediaWords::DB::connect_to_db;
        print "CONTROVERSY $controversy->{ name } \n";
        MediaWords::CM::Mine::dedup_stories( $db, $controversy );
    }
}

main();
