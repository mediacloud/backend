package MediaWords::Util::Timing;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Time::HiRes qw( gettimeofday tv_interval );

# Print out the name given; return a reference to the time of day
sub start_time
{
    my ( $name ) = @_;
    DEBUG "Begin $name ...";
    return [ gettimeofday ];
}

# Given a function name $name, and a start time, $t0, print how much time has elapsed
sub stop_time
{
    my ( $name, $t0 ) = @_;
    my $time_diff = tv_interval $t0, [ gettimeofday ];
    DEBUG "Finished $name in $time_diff seconds";
    return $time_diff;
}

1;
