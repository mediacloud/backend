package MediaWords::Controller::Api::V2::Media_Sets;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;

use strict;
use warnings;
use base 'Catalyst::Controller';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;

=head1 NAME

MediaWords::Controller::Media_Sets - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config(
    'default'   => 'application/json',
    'stash_key' => 'rest',
    'map'       => {

        #	   'text/html'          => 'YAML::HTML',
        'text/xml' => 'XML::Simple',

        # #         'text/x-yaml'        => 'YAML',
        'application/json'         => 'JSON',
        'text/x-json'              => 'JSON',
        'text/x-data-dumper'       => [ 'Data::Serializer', 'Data::Dumper' ],
        'text/x-data-denter'       => [ 'Data::Serializer', 'Data::Denter' ],
        'text/x-data-taxi'         => [ 'Data::Serializer', 'Data::Taxi' ],
        'application/x-storable'   => [ 'Data::Serializer', 'Storable' ],
        'application/x-freezethaw' => [ 'Data::Serializer', 'FreezeThaw' ],
        'text/x-config-general'    => [ 'Data::Serializer', 'Config::General' ],
        'text/x-php-serialization' => [ 'Data::Serializer', 'PHP::Serialization' ],
    },
    json_options => { relaxed => 1, pretty => 1, space_before => 2, indent => 1, space_after => 2 }
);

__PACKAGE__->config( json_options => { relaxed => 1, pretty => 1, space_before => 2, indent => 1, space_after => 2 } );

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

sub _add_data_to_media_sets
{

    my ( $self, $db, $media_set ) = @_;

    die "Not yet implemented";
}

## TODO move these to a centralized location instead of copying them in every API class
#A list top level object fields to include by default in API results unless all_fields is true
Readonly my $default_output_fields => [ qw ( name media_sets_id description ) ];

sub _purge_extra_fields :
{
    my ( $self, $obj ) = @_;

    my $new_obj = {};

    foreach my $default_output_field ( @{ $default_output_fields } )
    {
        $new_obj->{ $default_output_field } = $obj->{ $default_output_field };
    }

    return $new_obj;
}

sub _purge_extra_fields_obj_list
{
    my ( $self, $list ) = @_;

    return [ map { $self->_purge_extra_fields( $_ ) } @{ $list } ];
}

sub single : Local : ActionClass('+MediaWords::Controller::Api::V2::MC_Action_REST')
{
}

sub single_GET : Local
{
    my ( $self, $c, $media_sets_id ) = @_;

    my $query = "select s.* from media_sets s where media_sets_id = ? ";

    my $media_sets = $c->dbis->query( $query, $media_sets_id )->hashes();

    my $all_fields = $c->req->param( 'all_fields' );
    $all_fields //= 0;

    if ( !$all_fields )
    {
        $media_sets = $self->_purge_extra_fields_obj_list( $media_sets );
    }

    #$self->_add_data_to_media_sets( $c->dbis, $media_sets );

    $self->status_ok( $c, entity => $media_sets );
}

sub list : Local : ActionClass('+MediaWords::Controller::Api::V2::MC_Action_REST')
{
}

sub list_GET : Local
{
    my ( $self, $c ) = @_;

    say STDERR "starting list_GET";

    my $last_media_sets_id = $c->req->param( 'last_media_sets_id' );
    say STDERR "last_media_sets_id: $last_media_sets_id";

    $last_media_sets_id //= 0;

    my $all_fields = $c->req->param( 'all_fields' );
    $all_fields //= 0;

    my $rows = $c->req->param( 'rows' );
    say STDERR "rows $rows";

    $rows //= ROWS_PER_PAGE;

    my $media_sets =
      $c->dbis->query( "select s.* from media_sets s where media_sets_id > ? ORDER by media_sets_id asc limit ?",
        $last_media_sets_id, $rows )->hashes;

    if ( !$all_fields )
    {
        say STDERR "Purging extra fields in";
        say STDERR Dumper( $media_sets );
        $media_sets = $self->_purge_extra_fields_obj_list( $media_sets );
        say STDERR "Purging result:";
        say STDERR Dumper( $media_sets );
    }

    #$self->_add_data_to_media_sets( $c->dbis, $media_sets );

    $self->status_ok( $c, entity => $media_sets );
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
