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

sub main
{
    my ( $controversies_id );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions( "controversy=s" => \$controversies_id, ) || return;

    die( "Usage: $0 --controversy < id >" ) unless ( $controversies_id );

    my $db = MediaWords::DB::connect_to_db;

    $| = 1;

    return MediaWords::CM::Dump::dump_controversy( $db, $controversies_id );
}

main();

__END__
