package MediaWords::Util::Web;

# various functions for editing feed and medium tags

use strict;

use Encode;
use HTTP::Client::Parallel;
use HTTP::Request;
use List::Util;

use constant BATCH_SIZE => 20;

# use non-blocking io to get urls in parallel
sub ParallelGet
{
    my ($urls) = @_;

    my $responses = [];
    for (my $i = 0; $i < @{$urls}; $i += BATCH_SIZE) {
        my $httpp = HTTP::Client::Parallel->new;

        $httpp->{timeout} = 10;
        $httpp->{redirect} = 10;
        $httpp->{debug} = 1;

        my $end = List::Util::min($i + BATCH_SIZE, @{$urls} - 1);

        my @urls_slice = @{$urls}[$i .. $end];

        push(@{$responses}, @{$httpp->get(@urls_slice)});
    }
    
    return $responses;

}

1;
