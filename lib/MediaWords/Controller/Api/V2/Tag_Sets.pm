package MediaWords::Controller::Api::V2::Tag_Sets;
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
    return "tag_sets";
}

1;
