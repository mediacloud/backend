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
    return [ qw ( name url media_id ) ];
}

sub list_name_search_field
{
    return 'name';
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
