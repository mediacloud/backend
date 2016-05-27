package MediaWords::Controller::Api::V2::Topics::Story;
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
use Readonly;

Readonly my $DEFAULT_STORY_LIMIT => 10;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { story_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topic_id ) = @_;
    $c->stash->{ topic_id } = $topic_id;
}

sub story : Chained('apibase') : PathPart('story') : CaptureArgs(1)
{
    my ( $self, $c, $story_id ) = @_;
    $c->stash->{ story_id } = $story_id;
}

sub story_GET : Local
{

}

# /topics/*/story/*/inlinks
sub inlinks : Chained('story') : PathPart('inlinks') : Args(0) : ActionClass('MC_REST')
{

}

sub inlinks_GET : Local
{
    my ( $self, $c ) = @_;
    my $entity = {};
    $self->status_ok( $c, entity => $entity );
}

sub outlinks : Chained('story') : PathPart('outlinks') : Args(0) : ActionClass('MC_REST')
{

}

# /topics/*/story/*/outlinks
sub outlinks_GET : Local
{
    my ( $self, $c ) = @_;
    my $entity = {};
    $self->status_ok( $c, entity => $entity );
}

# /topics/*/story/*
sub story_id : Chained('apibase') : PathPart('story') : Args(1) : ActionClass('MC_REST')
{

}

sub story_id_GET : Local
{
    my ( $self, $c ) = @_;
    my $entity = {};
    $self->status_ok( $c, entity => $entity );
}

1;
