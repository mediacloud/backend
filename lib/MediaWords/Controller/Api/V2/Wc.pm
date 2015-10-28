package MediaWords::Controller::Api::V2::Wc;
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

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub list : Local : ActionClass('REST')
{
}

sub list_GET : Local : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    if ( $c->req->params->{ sample_size } && ( $c->req->params->{ sample_size } > 100_000 ) )
    {
        $c->req->params->{ sample_size } = 100_000;
    }

    my $wc = MediaWords::Solr::WordCounts->new( { db => $c->dbis, cgi_params => $c->req->params } );

    my $words = $wc->get_words;

    $self->status_ok( $c, entity => $words );
}

1;
