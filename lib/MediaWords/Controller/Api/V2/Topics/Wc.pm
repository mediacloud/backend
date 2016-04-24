package MediaWords::Controller::Api::V2::Topics::Wc;
use Modern::Perl "2015";
use MediaWords::CommonLibs;
use Data::Dumper;
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
use MediaWords::CM;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ) ] }, } );

sub apibase: Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
  my ($self, $c, $topic_id) = @_;
  $c->stash->{topic_id} = $topic_id;
}

sub wc: Chained('apibase') : PathPart('wc') : CaptureArgs(0)
{

}

sub list : Chained('wc') : Args(0) : ActionClass('REST')
{

}

sub list_GET
{
  my ( $self, $c ) = @_;

  if ( $c->req->params->{ sample_size } && ( $c->req->params->{ sample_size } > 100_000 ) )
  {
      $c->req->params->{ sample_size } = 100_000;
  }
  my $cdts = MediaWords::CM::get_time_slice_for_controversy($c->dbis, $c->stash->{ topic_id }, $c->req->params->{ timeslice }, $c->req->params->{ snapshot });
  if ($cdts) {
    my $query = "{~ controversy_dump_time_slice:$cdts->{ controversy_dump_time_slices_id } }";
    my $wc = MediaWords::Solr::WordCounts->new( { db => $c->dbis, q=> $query } );
    my $words = $wc->get_words;
    $self->status_ok( $c, entity => $words );
  } else {
    $self->status_bad_request( $c, message=> "could not retrieve word counts")
  }

}

1;
