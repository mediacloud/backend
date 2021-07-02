package MediaWords::Controller::Api::V2::MediaHealth;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;

use MediaWords::Util::ParseJSON;

=head1 NAME

MediaWords::Controller::MediaHealth - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

sub has_nested_data
{
    return 1;
}

sub _add_nested_data
{

    my ( $self, $db, $media ) = @_;

    my $ids_table = $db->get_temporary_ids_table( [ map { int( $_->{ media_id } ) } @{ $media } ] );

    my $gaps = $db->query( <<SQL,
        SELECT *
        FROM media_coverage_gaps
        WHERE media_id IN (
            SELECT id
            FROM $ids_table
        )
SQL
    )->hashes;

    my $gaps_lookup = {};
    map { push( @{ $gaps_lookup->{ $_->{ media_id } } }, $_ ) } @{ $gaps };

    map { $_->{ media_coverage_gaps } = $gaps_lookup->{ $_->{ media_id } } } @{ $media };

    return $media;
}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $media_ids = $c->req->params->{ 'media_id' };

    die( "media_id param required" ) unless ( $media_ids );

    $media_ids = [ $media_ids ] unless ( ref( $media_ids ) );

    $media_ids = [ map { int( $_ ) } @{ $media_ids } ];

    my $ids_table = $db->get_temporary_ids_table( $media_ids );

    my $media_health = $db->query( <<SQL
        SELECT *
        FROM media_health
        WHERE media_id IN (
            SELECT id
            FROM $ids_table
        )
        ORDER BY media_id
SQL
    )->hashes;

    my $mh_numify_fields = [
        qw/num_stories num_stories_y num_stories_w num_stories_90 num_sentences num_sentences_y num_sentences_w/,
        qw/num_sentences_y num_sentences_90 expected_sentences expected_stories/
    ];
    MediaWords::Util::ParseJSON::numify_fields( $media_health, $mh_numify_fields );

    my $gaps = $db->query( <<SQL
        SELECT *
        FROM media_coverage_gaps
        WHERE media_id IN (
            SELECT id
            FROM $ids_table
        )
        ORDER BY stat_week
SQL
    )->hashes;

    my $gap_numify_fields = [ qw/num_stories expected_stories num_sentences expected_sentences/ ];
    MediaWords::Util::ParseJSON::numify_fields( $gaps, $gap_numify_fields );

    my $gaps_lookup = {};
    map { my $mid = $_->{ media_id }; push( @{ $gaps_lookup->{ $mid } }, $_ ) } @{ $gaps };

    map { my $mid = $_->{ media_id }; $_->{ coverage_gaps_list } = $gaps_lookup->{ $mid } } @{ $media_health };

    $self->status_ok( $c, entity => $media_health );
}

sub single_GET
{
    die( 'not implemented' );
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
