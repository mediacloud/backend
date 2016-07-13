#!/usr/bin/env perl
#
# Add chunks of due stories from Bit.ly processing schedule to fetcher's job
# queue
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
use MediaWords::Util::Bitly::Schedule;

use Sys::RunAlone;

use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    # Stories to add at a single run
    Readonly my $CHUNK_SIZE => 1000;

    # Wait a little between adding each chunk in order to not fill up job
    # broker's queue too quickly
    Readonly my $DELAY_BETWEEN_CHUNKS => 30;

    INFO "Starting to add due stories to job broker's queue with $DELAY_BETWEEN_CHUNKS s delays between chunks...";
    while ( 1 )
    {
        INFO "Adding up to $CHUNK_SIZE due stories to job broker's queue...";
        my $stories_processed = MediaWords::Util::Bitly::Schedule::process_due_schedule_chunk( $db, $CHUNK_SIZE );
        INFO "Added $stories_processed due stories to job broker queue, waiting $DELAY_BETWEEN_CHUNKS s...";
        sleep( $DELAY_BETWEEN_CHUNKS );
    }
}

main();

# Required by Sys::RunAlone
__END__
