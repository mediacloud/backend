package MediaWords::Controller::Admin::Dashboards;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various pages for administering dashboards

use strict;
use warnings;
use parent 'Catalyst::Controller';

use MediaWords::Languages::Language;

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
            action           => $c->uri_for( '/admin/dashboards/create' ),
        }
    );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'dashboards/create.tt2';
        return;
    }

    # If the user unchecks the "public" checkbox, the value that is being sent
    # is undef
    $c->request->parameters->{ public } //= 0;

    $c->dbis->create_from_request( 'dashboards', $c->request, [ qw/name start_date end_date public/ ] );

    $c->response->redirect( $c->uri_for( '/admin/dashboards/list', { status_msg => 'Dashboard created.' } ) );
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
            action           => $c->uri_for( "/admin/dashboards/create_topic/$dashboards_id" ),
        }
    );

    $form->process( $c->request );

    my $query = $c->req->param( 'query' );
    if ( defined( $query ) && ( $query =~ /\W/ ) )
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

    my $language_code = $c->req->param( 'language' );
    if ( $language_code =~ /\W/ or bytes::length( $language_code ) < 2 or bytes::length( $language_code ) > 3 )
    {
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'dashboards/create_topic.tt2';
        $c->stash->{ error_msg } =
          'Language code must only include letters and numbers, and it should ' . 'be between 2 and 3 letters.';
        return;
    }
    my $lang = MediaWords::Languages::Language::language_for_code( $language_code );
    if ( !$lang )
    {
        $c->stash->{ form }      = $form;
        $c->stash->{ template }  = 'dashboards/create_topic.tt2';
        $c->stash->{ error_msg } = 'Language "' . $language_code . '" is not available.';
        return;
    }

    my $stemmed       = $lang->stem( $c->req->param( 'query' ) );
    my $stemmed_query = $stemmed->[ 0 ];

    $c->dbis->query(
        <<EOF,
        INSERT INTO dashboard_topics ( name, query, language, start_date, end_date, dashboards_id )
        VALUES (
            SUBSTRING( ?, 0, 256 ),
            SUBSTRING( ?, 0, 1024),
            ?,
            DATE_TRUNC( 'week', ?::date ),
            DATE_TRUNC( 'week', ?::date ) + INTERVAL '1 week',
            ?
        )
EOF
        $c->req->param( 'name' ),
        $stemmed_query,
        $language_code,
        $c->req->param( 'start_date' ),
        $c->req->param( 'end_date' ),
        $dashboards_id
    );

    $c->response->redirect(
        $c->uri_for( "/admin/dashboards/list_topics/$dashboards_id", { status_msg => 'Topic created.' } ) );
}

1;
