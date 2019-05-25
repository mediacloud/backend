package MediaWords::Controller::Api::V2::Downloads;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use base 'Catalyst::Controller';
use Moose;
use namespace::autoclean;

use MediaWords::DBI::Downloads::Store;

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
        if ( MediaWords::DBI::Downloads::Store::download_successful( $download ) )
        {
            my $raw_content = MediaWords::DBI::Downloads::Store::fetch_content( $db, $download );

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
