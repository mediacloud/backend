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
    my ( $start_date, $end_date, $period, $controversies_id, $cleanup_data );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions(
        "start_date=s"  => \$start_date,
        "end_date=s"    => \$end_date,
        "period=s"      => \$period,
        "controversy=s" => \$controversies_id,
        "cleanup_data!" => \$cleanup_data
    ) || return;

    die(
"Usage: $0 --controversy < id > [ --start_date < start date > --end_date < end date > --period < overall|weekly|monthly|all|custom > --cleanup_data ]"
    ) unless ( $controversies_id );

    my $db = MediaWords::DB::connect_to_db;

    return MediaWords::CM::Dump::dump_controversy( $db, $controversies_id, $start_date, $end_date, $period );
}

main();

__END__
