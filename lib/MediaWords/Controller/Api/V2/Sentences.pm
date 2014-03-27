package MediaWords::Controller::Api::V2::Sentences;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::StorySubsets;
use MediaWords::Controller::Api::V2::MC_Action_REST;
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

=head1 NAME

MediaWords::Controller::Media - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_REST_SimpleObject' }

use MediaWords::Tagger;

sub get_table_name
{
    return "story_sentences";
}

sub list : Local : ActionClass('+MediaWords::Controller::Api::V2::MC_Action_REST')
{
}

sub list_GET : Local
{
    my ( $self, $c ) = @_;

    say STDERR "starting list_GET";

    my $params = {};

    my $q  = $c->req->params->{ 'q' };
    my $fq = $c->req->params->{ 'fq' };

    my $start = $c->req->params->{ 'start' };
    my $rows  = $c->req->params->{ 'rows' };

    $rows  //= 1000;
    $start //= 0;

    $params->{ q }     = $q;
    $params->{ fq }    = $fq;
    $params->{ start } = $start;
    $params->{ rows }  = $rows;

    my $list = MediaWords::Solr::query( $params );

    $self->status_ok( $c, entity => $list );
}

##TODO merge with stories put_tags
sub put_tags : Local : ActionClass('+MediaWords::Controller::Api::V2::MC_Action_REST')
{
}

sub put_tags_PUT : Local
{
    my ( $self, $c ) = @_;
    my $subset = $c->req->data;

    my $story_tag = $c->req->params->{ 'sentence_tag' };

    my $story_tags;

    if ( ref $story_tag )
    {
        $story_tags = $story_tag;
    }
    else
    {
        $story_tags = [ $story_tag ];
    }

    say STDERR Dumper( $story_tags );

    $self->_add_tags( $c, $story_tags );

    $self->status_ok( $c, entity => $story_tags );

    return;
}

1;
