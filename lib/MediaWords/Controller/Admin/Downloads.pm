package MediaWords::Controller::Admin::Downloads;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use base 'Catalyst::Controller';

# MODULES
use Data::Dumper;
use DateTime;
use Encode;
use HTML::Entities;
use Readonly;

use MediaWords::Crawler::Engine;
use MediaWords::DBI::Downloads;

# CONSTANTS
Readonly my $ROWS_PER_PAGE => 100;

# METHODS

sub list : Local
{
    my ( $self, $c ) = @_;

    my $p        = $c->request->param( 'p' ) || 1;
    my $media_id = $c->request->param( 'm' );
    my $feeds_id = $c->request->param( 'f' );
    my $error    = $c->request->param( 'e' );

    my $query =
      "select d.* from downloads d, feeds f, media m " .
      "where d.feeds_id = f.feeds_id and f.media_id = m.media_id and d.download_time > now() - interval '1 month'";

    if ( $feeds_id )
    {
        $c->stash->{ feed } = $c->dbis->find_by_id( 'feeds', $feeds_id );
        $query .= " and d.feeds_id = " . ( $feeds_id + 0 );
    }
    elsif ( $media_id )
    {
        $c->stash->{ medium } = $c->dbis->find_by_id( 'media', $media_id );
        $query .= " and f.media_id = " . ( $media_id + 0 );
    }
    else
    {
        $query .= " and d.download_time > now() - interval '1 day'";
    }

    if ( $error )
    {
        $query .= " and d.state = 'error'";
    }

    $query .= " order by download_time desc";

    my $qph       = $c->dbis->query_paged_hashes( $query, $p, $ROWS_PER_PAGE );
    my $downloads = $qph->list();
    my $pager     = $qph->pager();

    for my $d ( @{ $downloads } )
    {
        $d->{ feed }   = $c->dbis->find_by_id( 'feeds', $d->{ feeds_id } );
        $d->{ medium } = $c->dbis->find_by_id( 'media', $d->{ feed }->{ media_id } );
    }

    $c->stash->{ downloads } = $downloads;
    $c->stash->{ pager }     = $pager;
    $c->stash->{ pager_url } = $c->uri_for( '/admin/downloads/list', { f => $feeds_id, m => $media_id, e => $error } );
    $c->stash->{ template }  = 'downloads/list.tt2';
}

sub view : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    if ( !$downloads_id )
    {
        $c->response->redirect( $c->uri_for( '/admin/downloads/list', { error_msg => 'no download specified' } ) );
        return;
    }

    my $download = $c->dbis->find_by_id( 'downloads', $downloads_id );

    if ( !$download )
    {
        die( "No such download" );
    }

    my $content;
    eval { $content = MediaWords::DBI::Downloads::fetch_content( $c->dbis, $download ) };
    if ( $@ )
    {
        $content = "Error fetching download:\n" . $@;
    }

    unless ( defined $content )
    {
        $content = "no content available for this download";
    }

    my $encoded_content = Encode::encode( 'utf-8', $content );

    $c->response->content_type( 'text/html; charset=UTF-8' );
    $c->response->content_length( bytes::length( $encoded_content ) );
    $c->response->body( $encoded_content );
}

sub view_extracted : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    if ( !$downloads_id )
    {
        $c->response->redirect( $c->uri_for( '/admin/downloads/list', { error_msg => 'no download specified' } ) );
        return;
    }

    my $download_text = $c->dbis->select( 'download_texts', '*', { downloads_id => $downloads_id } )->hash;

    if ( !$download_text )
    {
        die( "No such download" );
    }

    $c->response->content_type( 'text/plain; charset=UTF-8' );
    $c->response->content_length( bytes::length( $download_text->{ download_text } ) );

    $c->response->body( $download_text->{ download_text } );
}

sub redownload : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    unless ( $downloads_id )
    {
        die "downloads_id is unset.";
    }

    my $db = $c->dbis;

    INFO "Starting redownload of download $downloads_id...";

    my $download = $db->find_by_id( 'downloads', $downloads_id );

    my $handler = MediaWords::Crawler::Engine::handler_for_download( $db, $download );

    my $response = $handler->fetch_download( $db, $download );
    $handler->handle_response( $db, $download, $response );

    INFO "Finished redownload of download $downloads_id.";
}

1;
