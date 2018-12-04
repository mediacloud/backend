package MediaWords::Controller::Api::V2::Downloads;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use strict;
use warnings;
use base 'Catalyst::Controller';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;

=head1 NAME

MediaWords::Controller::Downloads - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

__PACKAGE__->config(    #
    action => {         #
        single => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },    # overrides "MC_REST_SimpleObject"
        list   => { Does => [ qw( ~AdminReadAuthenticated ~Throttled ~Logged ) ] },    # overrides "MC_REST_SimpleObject"
    }
);

sub list_optional_query_filter_field
{
    return 'feeds_id';
}

sub get_table_name
{
    return "downloads";
}

sub has_nested_data
{
    return 1;
}

sub _add_nested_data
{

    my ( $self, $db, $downloads ) = @_;

    foreach my $download ( @$downloads )
    {
        if ( MediaWords::DBI::Downloads::download_successful( $download ) )
        {
            my $raw_content = MediaWords::DBI::Downloads::fetch_content( $db, $download );

            $download->{ raw_content } = $raw_content;
        }
    }

    return $downloads;

}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
