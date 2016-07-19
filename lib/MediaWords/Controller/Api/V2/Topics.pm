package MediaWords::Controller::Api::V2::Topics;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub get_table_name
{
    return "topics";
}

1;
