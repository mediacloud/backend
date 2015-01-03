package MediaWords;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;

use Catalyst::Runtime '5.80';
use v5.8;

#use Catalyst::Runtime;

use DBIx::Simple::MediaWords;
use MediaWords::Util::Config;
use URI;
use Bundle::MediaWords;

# Set flags and add plugins for the application
#
#         -Debug: activates the debug mode for very useful log messages
#   ConfigLoader: will load the configuration from a YAML file in the
#                 application's home directory
# Plugin::Static::Simple: will serve static files from the application's root
#                 directory

use Catalyst qw/
  ConfigLoader
  ConfigDefaults
  Static::Simple
  Unicode
  StackTrace
  I18N
  Authentication
  Authorization::Roles
  Authorization::ACL
  Session
  Session::Store::File
  Session::State::Cookie
  /;

our $VERSION = '0.01';

use HTML::FormFu;
use HTML::FormFu::Unicode;

# Configure the application.
#
# Note that settings in mediawords.yml (or other external
# configuration file that you set up manually) take precedence
# over this when using ConfigLoader. Thus configuration
# details given here can function as a default configuration,
# with a external configuration file acting as an override for
# local deployment.

my $config = __PACKAGE__->config( -name => 'MediaWords' );

# Configure authentication scheme
__PACKAGE__->config( 'Plugin::Static::Simple' => { dirs => [ 'gexf' ] } );

# Exit an action chain when there is an error raised in any action (thus
# terminating the chain early)
__PACKAGE__->config( abort_chain_on_error_fix => 1 );

# Start the application
__PACKAGE__->setup;

# Access rules; created on the "disallow everything but explicitly allow this" basis
# (https://metacpan.org/module/Catalyst::Plugin::Authorization::ACL)
sub setup_acl()
{

    # Admin read-only interface
    my @acl_admin_readonly = qw|
      /admin/clusters/index
      /admin/clusters/view
      /admin/clusters/view_time_slice_map
      /admin/dashboards/list
      /admin/dashboards/list_topics
      /admin/downloads/list
      /admin/downloads/view
      /admin/downloads/view_extracted
      /admin/feeds/list
      /admin/gearman/view_log
      /admin/media/do_eval_rss_full_text
      /admin/media/do_find_likely_full_text_rss
      /admin/media/eval_rss_full_text
      /admin/media/find_likely_full_text_rss
      /admin/media/list
      /admin/media/media_tags_search_json
      /admin/media/search
      /admin/mediasets/list
      /admin/monitor/crawler_google_data_table
      /admin/monitor/index
      /admin/monitor/view
      /admin/queries/compare
      /admin/queries/index
      /admin/queries/list
      /admin/queries/sentences
      /admin/queries/stories
      /admin/queries/terms
      /admin/queries/view
      /admin/queries/view_media
      /admin/stats/index
      /admin/stats/media_tag_counts
      /admin/stories/list
      /admin/stories/retag
      /admin/stories/stories_query_json
      /admin/stories/tag
      /admin/stories/view
      /admin/topics/index
      /admin/topics/list
      /admin/users/list
      /admin/visualize
      |;

    # query-create role; can do everything admin-readonly can + create queries, dashboards,
    # dashboard topics, media sets
    my @acl_query_create = qw|
      /admin/clusters/create
      /admin/clusters/create_cluster_map
      /admin/clusters/create_polar_map
      /admin/dashboards/create
      /admin/dashboards/create_topic
      /admin/mediasets/create
      /admin/mediasets/edit_cluster_run
      /admin/mediasets/edit_cluster_run_do
      /admin/queries/create
      /admin/topics/create_do
      |;

    # media-edit role; can do everything admin-readonly can + add / edit media / feeds
    my @acl_media_edit = qw|
      /admin/downloads/disable_autoexclude
      /admin/downloads/disable_translation
      /admin/downloads/enable_autoexclude
      /admin/downloads/enable_translation
      /admin/downloads/mextract
      /admin/downloads/mextract_do
      /admin/downloads/mextract_random
      /admin/downloads/redownload
      /admin/downloads/useDeveloperUI
      /admin/downloads/useTrainerUI
      /admin/extractor_stats/index
      /admin/extractor_stats/list
      /admin/feeds/batch_create
      /admin/feeds/batch_create_do
      /admin/feeds/create
      /admin/feeds/create_do
      /admin/feeds/delete
      /admin/feeds/edit
      /admin/feeds/edit_do
      /admin/feeds/edit_tags
      /admin/feeds/edit_tags_do
      /admin/feeds/scrape
      /admin/feeds/scrape_import
      /admin/media/create_batch
      /admin/media/create_do
      /admin/media/delete
      /admin/media/skip_feeds
      /admin/media/skip_unmoderated_feed
      /admin/media/edit
      /admin/media/edit_do
      /admin/media/edit_tags
      /admin/media/edit_tags_do
      /admin/media/keep_single_feed
      /admin/media/merge
      /admin/media/moderate
      /admin/mediasets/create
      /admin/mediasets/edit_cluster_run
      /admin/mediasets/edit_cluster_run_do
      /admin/health
      /admin/health/list
      /admin/health/tag
      /admin/health/medium
      /admin/health/stories
      /admin/tags/edit
      /admin/tagsets/edit
      |;

    # stories-edit role; can do everything admin-readonly can + add / edit stories
    my @acl_stories_edit = qw|
      /admin/stories/add_tag
      /admin/stories/add_tag_do
      /admin/stories/delete_tag
      /admin/stories/edit
      /admin/tags/edit
      /admin/tagsets/edit
      |;

    # cm role; can access all cm pages + admin-readonly + media-edit + stories-edi
    my @acl_cm = qw|
      /admin/cm/
      /admin/gearman/view_log
      |;

    my @acl_search = qw|
      /search
      /search/index
      /search/wc
      /search/readme
      /search/diff
      |;

    foreach my $path ( @acl_admin_readonly )
    {
        __PACKAGE__->allow_access_if_any( $path, [ qw/admin-readonly query-create media-edit stories-edit cm/ ] );
    }

    foreach my $path ( @acl_query_create )
    {
        __PACKAGE__->allow_access_if_any( $path, [ qw/query-create/ ] );
    }

    foreach my $path ( @acl_media_edit )
    {
        __PACKAGE__->allow_access_if_any( $path, [ qw/media-edit cm/ ] );
    }

    foreach my $path ( @acl_stories_edit )
    {
        __PACKAGE__->allow_access_if_any( $path, [ qw/stories-edit cm/ ] );
    }

    for my $path ( @acl_cm )
    {
        __PACKAGE__->allow_access_if_any( $path, [ qw/cm/ ] );
    }

    for my $path ( @acl_search )
    {
        __PACKAGE__->allow_access_if_any( $path, [ qw/search/ ] );
    }

    # ---

    # All roles can access their profile
    __PACKAGE__->allow_access_if_any(
        "/admin/profile",
        [
            qw/
              admin
              admin-readonly
              query-create
              media-edit
              stories-edit
              cm
              stories-api
              search
              /
        ]
    );

    # Blanket rule for the rest of the administration controllers
    __PACKAGE__->deny_access_unless_any( "/admin",  [ qw/admin/ ] );
    __PACKAGE__->deny_access_unless_any( "/search", [ qw/admin/ ] );

    # Public interface
    __PACKAGE__->allow_access( "/dashboard" );
    __PACKAGE__->allow_access( "/login" );
    __PACKAGE__->allow_access( "/logout" );

    # we need to protect this with .htaccess until we can implement an easy to login via the api
    __PACKAGE__->allow_access( "/admin/query/sentences" );
    __PACKAGE__->allow_access( "/admin/query/wc" );

    __PACKAGE__->allow_access( "/admin/stop_server" );

}

setup_acl();

# Checks if current user can visit a specified action
# (similar to can_visit() from Catalyst::ActionRole::ACL)
sub acl_user_can_visit
{
    my ( $self, $path ) = @_;

    my $action = $self->dispatcher->get_action_by_path( $path );

    if (    Scalar::Util::blessed( $action )
        and $action->name ne "access_denied"
        and $action->name ne "ACL error rethrower" )
    {
        eval { $self->_acl_engine->check_action_rules( $self, $action ) };

        if ( my $err = $@ )
        {
            return 0;
        }
        else
        {
            return 1;
        }
    }

    # Fallback
    return 0;
}

sub uri_for
{
    my ( $self, $path, $args ) = @_;

    if ( !$self->config->{ mediawords }->{ base_url } )
    {
        shift( @_ );
        return $self->SUPER::uri_for( @_ );
    }

    my $uri = URI->new( $self->config->{ mediawords }->{ base_url } . $path );

    if ( $args )
    {
        $uri->query_form( $args );
    }

    my $uri_string = $uri->as_string();

    while ( $uri_string =~ s~(https?\://.*)//~$1/~g ) { }

    return $uri_string;
}

sub create_form
{
    my ( $self, $args ) = @_;

    my $ret = HTML::FormFu::Unicode->new( $args );

    return $ret;
}

# Redirect unauthenticated users to login page
sub acl_access_denied
{
    my ( $c, $class, $action, $err ) = @_;

    if ( $c->user_exists )
    {
        $c->log->debug( 'User has been found, is not allowed to access page /' . $action );

        # Show the "unauthorized" message
        $c->res->body( 'You are not allowed to access page /' . $action );
        $c->res->status( 403 );
    }
    else
    {
        $c->log->debug( 'User not found, forwarding to /login' );

        # Redirect the user to the login page
        $c->response->redirect( $c->uri_for( '/login', { url => $c->req->uri } ) );
    }

    # Continue denying access
    return 0;
}

# shortcut to dbis model
sub dbis
{

    return $_[ 0 ]->model( 'DBIS' )->dbis( $_[ 0 ]->req );
}

=head1 NAME

MediaWords - Catalyst based application

=head1 SYNOPSIS

    script/mediawords_server.pl

=head1 DESCRIPTION

[enter your description here]

=head1 SEE ALSO

L<MediaWords::Controller::Root>, L<Catalyst>

=head1 AUTHOR

Hal Roberts

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
