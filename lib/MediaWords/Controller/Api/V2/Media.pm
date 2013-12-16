package MediaWords::Controller::Api::V2::Media;
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

MediaWords::Controller::Media - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'Catalyst::Controller::REST' }

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
);

__PACKAGE__->config( json_options => { relaxed => 1, pretty => 1, space_before => 1, space_after => 1 } );

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

sub _add_data_to_media
{

    my ( $self, $db, $media ) = @_;

    foreach my $media_source ( @{ $media } )
    {
        say STDERR "adding media_source tags ";
        my $media_source_tags = $db->query(
"select tags.tags_id, tags.tag, tag_sets.tag_sets_id, tag_sets.name as tag_set from media_tags_map natural join tags natural join tag_sets where media_id = ? ORDER by tags_id",
            $media_source->{ media_id }
        )->hashes;
        $media_source->{ media_source_tags } = $media_source_tags;
    }

    return $media;

}

sub media_query : Local : ActionClass('REST')
{
}

sub media_query_GET : Local
{
    my ( $self, $c, $media_id ) = @_;

    my $query = "select s.* from media s where media_id = ? ";

    my $media = $c->dbis->query( $query, $media_id )->hashes();

    $self->_add_data_to_media( $c->dbis, $media );

    $self->status_ok( $c, entity => $media );
}

sub all_processed : Local : ActionClass('REST')
{
}

sub all_processed_GET : Local
{
    my ( $self, $c ) = @_;

    say STDERR "starting media_query_json";

    my $last_processed_media_id = $c->req->param( 'last_processed_media_id' );
    say STDERR "last_processed_media_id: $last_processed_media_id";

    $last_processed_media_id //= 0;

    my $media = $c->dbis->query( "select s.* from media s where media_id > ? ORDER by media_id asc limit ?",
        $last_processed_media_id, ROWS_PER_PAGE )->hashes;

    $self->_add_data_to_media( $c->dbis, $media );

    $self->status_ok( $c, entity => $media );
}

=head1 AUTHOR

Alexandra J. Sternburg

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
