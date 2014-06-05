package MediaWords::Controller::Api::V2::Tags;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;
use MediaWords::DBI::StorySubsets;
use MediaWords::Controller::Api::V2::MC_REST_SimpleObject;

use Moose;
use namespace::autoclean;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

sub get_table_name
{
    return "tags";
}

sub list_query_filter_field
{
    return 'tag_sets_id';
}

1;
