package MediaWords::Controller::Api::V2::Stories;
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

BEGIN { extends 'MediaWords::Controller::Api::V2::StoriesBase' }

__PACKAGE__->config(
    action => {
        single_GET   => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        list_GET     => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
        put_tags_PUT => { Does => [ qw( ~NonPublicApiKeyAuthenticated ~Throttled ~Logged ) ] },
    }
);

use constant ROWS_PER_PAGE => 20;

use MediaWords::Tagger;

sub put_tags : Local : ActionClass('REST')
{
}

sub put_tags_PUT : Local
{
    my ( $self, $c ) = @_;

    my $subset = $c->req->data;

    my $story_tag = $c->req->params->{ 'story_tag' };

    my $story_tags;

    if ( ref $story_tag )
    {
        $story_tags = $story_tag;
    }
    else
    {
        $story_tags = [ $story_tag ];
    }

    # say STDERR Dumper( $story_tags );

    $self->_add_tags( $c, $story_tags );

    $self->status_ok( $c, entity => $story_tags );

    return;
}

=head1 AUTHOR

David Larochelle

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
