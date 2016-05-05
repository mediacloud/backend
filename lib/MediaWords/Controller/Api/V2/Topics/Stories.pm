package MediaWords::Controller::Api::V2::Topics::Stories;
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

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topic_id ) = @_;
    $c->stash->{ topic_id } = $topic_id;
}

sub stories : Chained('apibase') : PathPart('stories') : CaptureArgs(0)
{

}

sub list : Chained('stories') : Args(0) : ActionClass('REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;
    my $db   = $c->dbis;
    my $cdts = MediaWords::CM::get_time_slice_for_controversy(
        $c->dbis,
        $c->stash->{ topic_id },
        $c->req->params->{ timeslice },
        $c->req->params->{ snapshot }
    );
    my $entity = {};
    $entity->{ timeslice } = $cdts;

    if ( $cdts )
    {
        $entity->{ stories } =
          $db->query( <<SQL, $cdts->{ controversy_dump_time_slices_id }, $cdts->{ controversy_dumps_id } )->hashes;
select * from cd.story_link_counts slc
  join cd.stories s on slc.stories_id = s.stories_id
  where slc.controversy_dump_time_slices_id = \$1
  and s.controversy_dumps_id = \$2
  order by slc.inlink_count desc, s.stories_id
SQL
        $self->status_ok( $c, entity => $entity );
    }
    else
    {
        $self->status_bad_request( $c, message => "unable to find snapshot and timeslice" );
    }
}

1;
