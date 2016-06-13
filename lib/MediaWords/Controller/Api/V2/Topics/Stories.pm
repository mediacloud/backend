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
use Readonly;

Readonly my $DEFAULT_STORY_LIMIT => 10;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topic_id ) = @_;
    $c->stash->{ topic_id } = $topic_id;
}

sub stories : Chained('apibase') : PathPart('stories') : CaptureArgs(0)
{

}

sub list : Chained('stories') : Args(0) : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $db   = $c->dbis;
    my $cdts = MediaWords::CM::require_time_slice_for_controversy(
        $c->dbis,
        $c->stash->{ topic_id },
        $c->req->params->{ timeslice },
        $c->req->params->{ snapshot }
    );

    my $sort_param = $c->req->params->{ sort } || 'inlink';

    # md5 hashing is to make tie breaks random but consistent
    my $sort_clause =
      ( $sort_param eq 'social' )
      ? 'slc.bitly_click_count desc nulls last, md5( s.stories_id::text )'
      : 'slc.inlink_count desc, md5( s.stories_id::text )';

    my $cdts_id = $cdts->{ controversy_dump_time_slices_id };
    my $cd_id   = $cdts->{ controversy_dumps_id };

    my ( $stories, $continuation_id ) = $self->do_continuation_query( $c, <<SQL, [ $cdts_id, $cd_id ] );
select *
    from cd.story_link_counts slc
        join cd.stories s on slc.stories_id = s.stories_id
    where slc.controversy_dump_time_slices_id = \$1
        and s.controversy_dumps_id = \$2
    order by $sort_clause
SQL

    my $entity = { timeslice => $cdts, stories => $stories, continuation_id => $continuation_id };
    $self->status_ok( $c, entity => $entity );

}

1;
