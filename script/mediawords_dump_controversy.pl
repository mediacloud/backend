#!/usr/bin/env perl

# dump various controversy queries to csv and build a gexf file

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CM::Dump;
use MediaWords::DB;
use MediaWords::DBI::Controversies;

sub main
{
    my ( $controversy_opt );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    Getopt::Long::GetOptions( "controversy=s" => \$controversy_opt ) || return;

    die( "Usage: $0 --controversy < id >" ) unless ( $controversy_opt );

    my $db = MediaWords::DB::connect_to_db;

    my $controversies = MediaWords::DBI::Controversies::require_controversies_by_opt( $db, $controversy_opt );

    for my $controversy ( @{ $controversies } )
    {
        $db->disconnect;
        $db = MediaWords::DB::connect_to_db;
        print "CONTROVERSY $controversy->{ name } \n";
        MediaWords::CM::Dump::dump_controversy( $db, $controversy->{ controversies_id } );
    }
}

main();

__END__
