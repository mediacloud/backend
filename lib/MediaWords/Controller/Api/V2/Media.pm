package MediaWords::Controller::Api::V2::Media;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;
use MediaWords::Solr;
use MediaWords::CM::Dump;

=head1 NAME

MediaWords::Controller::Media - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

sub get_table_name
{
    return "media";
}

sub has_nested_data
{
    return 1;
}

sub _add_nested_data
{

    my ( $self, $db, $media ) = @_;

    foreach my $media_source ( @{ $media } )
    {
        # say STDERR "adding media_source tags ";
        $media_source->{ media_source_tags } = $db->query( <<END, $media_source->{ media_id } )->hashes;
select t.tags_id, t.tag, t.label, t.description, ts.tag_sets_id, ts.name as tag_set,
        ( t.show_on_media or ts.show_on_media ) show_on_media,
        ( t.show_on_stories or ts.show_on_stories ) show_on_stories
    from media_tags_map mtm
        join tags t on ( mtm.tags_id = t.tags_id )
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where mtm.media_id = ?
    order by t.tags_id
END
    }

    return $media;
}

sub default_output_fields
{
    my ( $self ) = @_;

    my $fields = [ qw ( name url media_id ) ];

    push( @{ $fields }, qw ( inlink_count outlink_count story_count ) ) if ( $self->{ topic_media } );

    return $fields;
}

sub list_name_search_field
{
    return 'name';
}

sub order_by_clause
{
    my ( $self ) = @_;

    return $self->{ topic_media } ? 'inlink_count desc' : 'media_id asc';
}

# if topic_timespans_id is specified, create a temporary
# table with the media name that supercedes the normal media table
# but includes only media in the given topic timespan and
# has the topic metric data
sub _create_topic_media_table
{
    my ( $self, $c ) = @_;

    my $timespans_id = $c->req->params->{ timespans_id };
    my $timespan_mode = $c->req->params->{ topic_mode } || '';

    return unless ( $timespans_id );

    $self->{ topic_media } = 1;

    my $live = $timespan_mode eq 'live' ? 1 : 0;

    my $db = $c->dbis;

    my $timespan = $db->find_by_id( 'timespans', $timespans_id )
      || die( "Unable to find timespan with id '$timespans_id'" );

    my $topic = $db->query( <<END, $timespan->{ snapshots_id } )->hash;
select * from topics where topics_id in (
    select topics_id from snapshots where snapshots_id = ? )
END

    $db->begin;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $timespan, $topic, $live );

    $db->query( <<END );
create temporary table media as
    select m.name, m.url, mlc.*
        from media m join dump_medium_link_counts mlc on ( m.media_id = mlc.media_id )
END

    $db->commit;
}

sub get_extra_where_clause
{
    my ( $self, $c ) = @_;

    my $clauses = [];

    if ( my $tags_id = $c->req->params->{ tags_id } )
    {
        $tags_id += 0;

        push( @{ $clauses },
            "and media_id in ( select mtm.media_id from media_tags_map mtm where mtm.tags_id = $tags_id )" );
    }

    if ( my $q = $c->req->params->{ q } )
    {
        my $solr_params = { q => $q };
        my $media_ids = MediaWords::Solr::search_for_media_ids( $c->dbis, $solr_params );

        my $ids_table = $c->dbis->get_temporary_ids_table( $media_ids );

        push( @{ $clauses }, "and media_id in ( select id from $ids_table )" );
    }

    return @{ $clauses } ? join( "  ", @{ $clauses } ) : '';
}

sub list_GET : Local
{
    my ( $self, $c ) = @_;

    $self->_create_topic_media_table( $c );

    return $self->SUPER::list_GET( $c );
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
