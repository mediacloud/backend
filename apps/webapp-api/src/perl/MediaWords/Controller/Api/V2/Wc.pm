package MediaWords::Controller::Api::V2::Wc;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use MediaWords::Solr;
use MediaWords::Solr::WordCounts;
use MediaWords::Solr::WordCountsOldStopwords;   # FIXME remove once stopword comparison is over


=head1 NAME

MediaWords::Controller::Media - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index 

=cut

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub list : Local : ActionClass('MC_REST')
{
}

sub list_GET : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    my $sample_size = int( $c->req->params->{ sample_size } // 1000 );

    if ( $sample_size and $sample_size > 100_000 )
    {
        $sample_size = 100_000;
    }

    $c->req->params->{ sample_size } = $sample_size;

    my $wc;
    if ( $c->req->params->{ old_stopwords } ) {
        # FIXME remove once stopword comparison is over
        $wc = MediaWords::Solr::WordCountsOldStopwords->new( { db => $c->dbis, cgi_params => $c->req->params } );
    } else {
        $wc = MediaWords::Solr::WordCounts->new( { db => $c->dbis, cgi_params => $c->req->params } );
    }

    my $words = $wc->get_words;

    $self->status_ok( $c, entity => $words );
}

1;
