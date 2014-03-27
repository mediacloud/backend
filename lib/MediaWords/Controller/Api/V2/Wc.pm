package MediaWords::Controller::Api::V2::Wc;
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

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

use MediaWords::Tagger;

sub list : Local : ActionClass('+MediaWords::Controller::Api::V2::MC_Action_REST')
{
}

sub list_GET : Local : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $q  = $c->req->parameters->{ 'q' };
    my $fq = $c->req->parameters->{ 'fq' };

    my $words = MediaWords::Solr::count_words( { q => $q, fq => $fq } );

    $self->status_ok( $c, entity => $words );
}

1;
