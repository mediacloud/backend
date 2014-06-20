package MediaWords::Controller::Api::V2::Stories_Public;
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

use MediaWords::DBI::Stories;
use MediaWords::Solr;

=head1 NAME

MediaWords::Controller::Stories - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

sub has_nested_data
{
    return 1;
}

sub get_table_name
{
    return "stories";
}

sub _add_nested_data
{
    my ( $self, $db, $stories ) = @_;

    return unless ( $stories && @{ $stories } );

    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( [ map { $_->{ stories_id } } @{ $stories } ] );

    my $tag_data = $db->query( <<END )->hashes;
select s.stories_id, t.tags_id, t.tag, ts.tag_sets_id, ts.name as tag_set
    from stories_tags_map s
        join tags t on ( t.tags_id = s.tags_id )
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where s.stories_id in ( select id from $ids_table )
    order by t.tags_id
END
    MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $tag_data, 'story_tags' );

    $db->commit;

    return $stories;
}

sub _get_list_last_id_param_name
{
    my ( $self, $c ) = @_;

    return "last_processed_stories_id";
}

sub _get_object_ids
{
    my ( $self, $c, $last_id, $rows ) = @_;

    my $q = $c->req->param( 'q' ) || '*:*';

    my $fq = $c->req->params->{ fq } || [];
    $fq = [ $fq ] unless ( ref( $fq ) );

    return MediaWords::Solr::search_for_processed_stories_ids( $q, $fq, $last_id, $rows );
}

sub _fetch_list
{
    my ( $self, $c, $last_id, $table_name, $id_field, $rows ) = @_;

    $rows //= 20;
    $rows = List::Util::min( $rows, 10_000 );

    my $ps_ids = $self->_get_object_ids( $c, $last_id, $rows );

    return [] unless ( @{ $ps_ids } );

    my $db = $c->dbis;

    $db->begin;

    my $ids_table = $db->get_temporary_ids_table( $ps_ids );

    my $stories = $db->query( <<END )->hashes;
with ps_ids as

    ( select processed_stories_id, stories_id
        from processed_stories
        where processed_stories_id in ( select id from $ids_table ) )

select s.stories_id, s.url, s.guid, s.publish_date, s.collect_date, p.processed_stories_id
    from stories s join ps_ids p on ( s.stories_id = p.stories_id )
    order by processed_stories_id asc limit $rows
END

    $db->commit;

    return $stories;
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;

