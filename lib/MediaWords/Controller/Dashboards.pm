package MediaWords::Controller::Dashboards;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# various pages for administering dashboards

use strict;
use warnings;
use parent 'Catalyst::Controller';

use MediaWords::Util::Stemmer;

# list all dashboards
sub list : Local
{
    my ( $self, $c ) = @_;

    my $dashboards = $c->dbis->query( "select * from dashboards order by name" )->hashes;

    $c->stash->{ dashboards } = $dashboards;

    $c->stash->{ template } = 'dashboards/list.tt2';
}

# create a new dashboard
sub create : Local
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/dashboard.yml',
            method           => 'post',
            action           => $c->uri_for( '/dashboards/create' ),
        }
    );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'dashboards/create.tt2';
        return;
    }

    $c->dbis->create_from_request( 'dashboards', $c->request, [ qw/name start_date end_date/ ] );

    $c->response->redirect( $c->uri_for( '/dashboards/list', { status_msg => 'Dashboard created.' } ) );
}

# list all topics for the dashboard
sub list_topics : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    $dashboards_id || die( "no dashboards_id in path" );

    my $dashboard_topics =
      $c->dbis->query( "select * from dashboard_topics where dashboards_id = ? order by dashboard_topics_id",
        $dashboards_id )->hashes;

    $c->stash->{ dashboards_id }    = $dashboards_id;
    $c->stash->{ dashboard_topics } = $dashboard_topics;

    $c->stash->{ template } = 'dashboards/list_topics.tt2';
}

sub create_topic : Local
{
    my ( $self, $c, $dashboards_id ) = @_;

    $dashboards_id || die( "no dashboards_id in path" );

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/dashboard_topic.yml',
            method           => 'post',
            action           => $c->uri_for( "/dashboards/create_topic/$dashboards_id" ),
        }
    );

    $form->process( $c->request );

    my $query = $c->req->param( 'query' );
    if ( $query =~ /\W/ )
    {
        $c->stash->{ form }      = $form;
        $c->stash->{ template }  = 'dashboards/create_topic.tt2';
        $c->stash->{ error_msg } = 'Query must only include letters and numbers';
        return;
    }

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'dashboards/create_topic.tt2';
        return;
    }

    my $stemmer       = MediaWords::Util::Stemmer->new;
    my $stemmed       = $stemmer->stem( $c->req->param( 'query' ) );
    my $stemmed_query = $stemmed->[ 0 ];

    $c->dbis->query(
        "insert into dashboard_topics ( name, query, start_date, end_date, dashboards_id ) " .
          " values( substring( ?, 0, 256 ), substring( ?, 0, 1024) , " .
          "   date_trunc( 'week', ?::date ), date_trunc( 'week', ?::date ) + interval '1 week', ? ) ",
        $c->req->param( 'name' ),
        $stemmed_query,
        $c->req->param( 'start_date' ),
        $c->req->param( 'end_date' ),
        $dashboards_id
    );

    $c->response->redirect( $c->uri_for( "/dashboards/list_topics/$dashboards_id", { status_msg => 'Topic created.' } ) );
}

1;
