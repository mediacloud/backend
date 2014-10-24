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

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

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

    foreach my $media_source ( @{ $media } )
    {
        # say STDERR "adding media_sets ";
        $media_source->{ media_sets } = $db->query( <<END, $media_source->{ media_id } )->hashes;
select ms.media_sets_id, ms.name, ms.description
    from media_sets_media_map msmm
        join media_sets ms on ( msmm.media_sets_id = ms.media_sets_id ) 
    where msmm.media_id = ? and
        ms.set_type = 'collection'
    ORDER by ms.media_sets_id
END
    }

    return $media;
}

sub default_output_fields
{
    my ( $self ) = @_;

    my $fields = [ qw ( name url media_id ) ];

    push( @{ $fields }, qw ( inlink_count outlink_count story_count ) ) if ( $self->{ controversy_media } );

    return $fields;
}

sub list_name_search_field
{
    return 'name';
}

sub order_by_clause
{
    my ( $self ) = @_;

    return $self->{ controversy_media } ? 'inlink_count desc' : 'media_id asc';
}

# if controversy_time_slices_id is specified, create a temporary
# table with the media name that supercedes the normal media table
# but includes only media in the given controversy time slice and
# has the controversy metric data
sub _create_controversy_media_table
{
    my ( $self, $c ) = @_;

    my $cdts_id = $c->req->params->{ controversy_dump_time_slices_id };
    my $cdts_mode = $c->req->params->{ controversy_mode } || '';

    return unless ( $cdts_id );

    $self->{ controversy_media } = 1;

    my $live = $cdts_mode eq 'live' ? 1 : 0;

    my $db = $c->dbis;

    my $cdts = $db->find_by_id( 'controversy_dump_time_slices', $cdts_id )
      || die( "Unable to find controversy_dump_time_slice with id '$cdts_id'" );

    my $controversy = $db->query( <<END, $cdts->{ controversy_dumps_id } )->hash;
select * from controversies where controversies_id in ( 
    select controversies_id from controversy_dumps where controversy_dumps_id = ? )
END

    $db->begin;

    MediaWords::CM::Dump::setup_temporary_dump_tables( $db, $cdts, $controversy, $live );

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

    # we have to setup a transaction here to be able to use the temporary table from
    # _get_temporary_table_ids in get_extra_where_clause
    $c->dbis->begin;

    my $r;
    eval {
        $self->_create_controversy_media_table( $c );

        my $r = $self->SUPER::list_GET( $c );
    };

    if ( $@ )
    {
        $c->dbis->rollback;
        die( $@ );
    }
    else
    {
        $c->dbis->commit;
    }

    return $r;
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
