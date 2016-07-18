package MediaWords::Controller::Api::V2::Controversies;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';
use Moose;
use namespace::autoclean;

Readonly my $DEFAULT_STORY_LIMIT => 10;

BEGIN { extends 'MediaWords::Controller::Api::V2::MC_Controller_REST' }

__PACKAGE__->config( action => { list_GET => { Does => [ qw( ~PublicApiKeyAuthenticated ~Throttled ~Logged ) ] }, } );

sub list : Local : ActionClass('MC_REST')
{

}

sub list_GET
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $controversies = $db->query( <<SQL )->hashes;
select
        t.topics_id controversies_id,
        t.name,
        t.pattern,
        t.solr_seed_query,
        t.solr_seed_query_run,
        t.description,
        t.state,
        t. error_message
    from topics t
        left join snapshots snap using ( topics_id )
    group by t.topics_id
    order by t.state = 'ready', t.state,  max( coalesce( snap.snapshot_date, '2000-01-01'::date ) ) desc
SQL

    $self->status_ok( $c, entity => $controversies );

}

1;
