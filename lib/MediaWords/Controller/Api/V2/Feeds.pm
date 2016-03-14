package MediaWords::Controller::Api::V2::Feeds;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;
use MediaWords::Controller::Api::V2::MC_REST_SimpleObject;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

sub default_output_fields
{
    return [ qw ( name url media_id feeds_id feed_type ) ];
}

sub get_table_name
{
    return "feeds";
}

sub list_query_filter_field
{
    return 'media_id';
}

1;
