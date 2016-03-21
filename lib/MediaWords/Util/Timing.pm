package MediaWords::Util::Timing;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use Time::HiRes qw( gettimeofday tv_interval );

require Exporter;

our @ISA    = qw( Exporter );
our @EXPORT = qw( start_time stop_time );

# Print out the name given; return a reference to the time of day
sub start_time
{
    my ( $name ) = @_;
    print STDERR "Begin $name ...\n";
    return [ gettimeofday ];
}

# Given a function name $name, and a start time, $t0, print how much time has elapsed
sub stop_time
{
    my ( $name, $t0 ) = @_;
    my $time_diff = tv_interval $t0, [ gettimeofday ];
    print STDERR "Finished $name in $time_diff seconds\n\n";
    return $time_diff;
}

1;
