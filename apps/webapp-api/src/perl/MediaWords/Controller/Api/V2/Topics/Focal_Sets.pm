package MediaWords::Controller::Api::V2::Topics::Focal_Sets;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Moose;
use namespace::autoclean;

use MediaWords::DBI::Timespans;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list => { Does => [ qw( ~TopicsReadAuthenticated ~Throttled ~Logged ) ] }, } );

sub apibase : Chained('/') : PathPart('api/v2/topics') : CaptureArgs(1)
{
    my ( $self, $c, $topics_id ) = @_;
    $c->stash->{ topics_id } = $topics_id;
}

sub focal_sets : Chained('apibase') : PathPart('focal_sets') : CaptureArgs(0)
{
}

sub list : Chained('focal_sets') : Args(0) : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $topics_id    = $c->stash->{ topics_id };
    my $timespan     = MediaWords::DBI::Timespans::set_timespans_id_param( $c );
    my $snapshots_id = $timespan->{ snapshots_id };

    my $focal_sets = $db->query( <<SQL, $snapshots_id )->hashes;
select focal_sets_id, name, description, false is_exclusive
    from focal_sets
    where snapshots_id = \$1
    order by name desc
SQL

    my $fs_ids = [ map { int( $_->{ focal_sets_id } ) } @{ $focal_sets } ];
    my $ids_table = $db->get_temporary_ids_table( $fs_ids );

    my $foci = $db->query( <<SQL )->hashes;
select foci_id, name, description, arguments->>'query' query, focal_sets_id
    from foci
    where focal_sets_id in ( select id from $ids_table )
SQL

    my $foci_lookup = {};
    map { push( @{ $foci_lookup->{ int( $_->{ focal_sets_id } ) } }, $_ ) } @{ $foci };

    map { $_->{ foci } = $foci_lookup->{ int( $_->{ focal_sets_id } ) } || [] } @{ $focal_sets };

    $self->status_ok( $c, entity => { focal_sets => $focal_sets } );
}

1;
