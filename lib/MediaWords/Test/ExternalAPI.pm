package MediaWords::Test::ExternalAPI;

=head1 NAME

MediaWords::Test::ExternalAPI - functions to help testing external apis

=cut

use strict;
use warnings;

=head1 FUNCTIONS

=head2 use_external_api()

Returns true if $ENV{ MC_USE_EXTERNAL_API } is set.  This is just an advisory signal to tests that can use it
to decide whether to send requests to the actual api or to use a local mock api as implemented by the particular
test.  In general, tests should implement a local mock api test that runs by default.

=cut

sub use_external_api()
{
    return $ENV{ MC_USE_EXTERNAL_API } ? 1 : undef;
}

1;
