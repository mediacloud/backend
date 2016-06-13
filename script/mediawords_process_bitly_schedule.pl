#!/usr/bin/env perl
#
# Add stories to Bit.ly processing queue
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
use MediaWords::Job::Bitly::FetchStoryStats;

use Sys::RunAlone;

use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    MediaWords::Util::Bitly::Schedule::process_due_schedule( $db );
}

main();

# Required by Sys::RunAlone
__END__
