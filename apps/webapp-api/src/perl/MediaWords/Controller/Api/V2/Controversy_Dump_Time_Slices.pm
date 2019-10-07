package MediaWords::Controller::Api::V2::Controversy_Dump_Time_Slices;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
use namespace::autoclean;

=head1 NAME

MediaWords::Controller::Controversy_Dump_Time_Slices - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

sub get_table_name
{
    return "controversy_dump_time_slices";
}

sub list_optional_query_filter_field
{
    return [ qw(controversy_dumps_id tags_id period start_date end_date) ];
}

sub order_by_clause
{
    return "controversy_dumps_id, tags_id desc, period, start_date, end_date";
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
