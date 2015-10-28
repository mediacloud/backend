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

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

sub get_table_name
{
    return "media_sets";
}

sub has_nested_data
{
    return 1;
}

sub _add_nested_data
{

    my ( $self, $db, $media_sets ) = @_;

    #say STDERR "adding nested data ";

    foreach my $media_set ( @{ $media_sets } )
    {
        #say STDERR "adding media tags ";
        my $media = $db->query(
"select media.name, media.media_id, media.url from media_sets_media_map natural join media where media_sets_id = ? ORDER by media_id, media_sets_media_map_id ",
            $media_set->{ media_sets_id }
        )->hashes;
        $media_set->{ media } = $media;
    }
}

sub default_output_fields
{
    return [ qw ( name media_sets_id description ) ];
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE


=cut

1;
