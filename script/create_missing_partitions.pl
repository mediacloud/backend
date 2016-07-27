#!/usr/bin/env perl
#
# Create missing partitions for for partitioned tables
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::DB;

use Sys::RunAlone;

use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    # Wait for an hour between attempts to create new partitions
    Readonly my $DELAY_BETWEEN_ATTEMPTS => 60 * 60;

    INFO "Starting to create missing partitions...";
    while ( 1 )
    {
        INFO "Creating missing partitions...";

        my $db = MediaWords::DB::connect_to_db;
        $db->query( 'SELECT create_missing_partitions()' );
        $db->disconnect;

        INFO "Created missing partitions, sleeping for $DELAY_BETWEEN_ATTEMPTS seconds.";
        sleep( $DELAY_BETWEEN_ATTEMPTS );
    }
}

main();

# Required by Sys::RunAlone
__END__
