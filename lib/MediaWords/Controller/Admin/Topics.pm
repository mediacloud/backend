package MediaWords::Controller::Admin::Topics;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use URI::Escape;
use DBIx::Simple;

sub index : Path : Args(0)
{

    return list( @_ );
}

# list the possible word cloud topics
sub list : Local
{
    my ( $self, $c ) = @_;

    my $topics =
      $c->dbis->query( "select w.*, t.tag as source_tag_name " .
          "  from word_cloud_topics w left join tags t on w.source_tags_id = t.tags_id " .
          "    where w.type = 'words' order by w.word_cloud_topics_id" )->hashes;

    $c->stash->{ topics }   = $topics;
    $c->stash->{ template } = 'topics/list.tt2';
}

# create a new topic
sub create_do : Local
{
    my ( $self, $c ) = @_;

    my $query           = $c->request->param( 'query' );
    my $start_date      = $c->request->param( 'start_date' );
    my $end_date        = $c->request->param( 'end_date' );
    my $source_tag_name = $c->request->param( 'source_tag_name' );
    my $set_tag_names   = $c->request->param( 'set_tag_names' );
    my $creator         = $c->request->param( 'creator' );

    if ( !( $query && $start_date && $end_date && $source_tag_name && $set_tag_names && $creator ) )
    {
        my $msg = 'query, start_date, end_date, source_tag_name, set_tag_names, and creator are all required.';
        $c->response->redirect( $c->uri_for( "/admin/topics/list/", { error_msg => $msg } ) );
        return;
    }

    if ( $start_date !~ /^\d\d\d\d-\d\d-\d\d$/ )
    {
        $c->response->redirect(
            $c->uri_for( "/admin/topics/list/", { error_msg => 'start_date must be in the form YYYY-MM-DD' } ) );
        return;
    }

    if ( $end_date !~ /^\d\d\d\d-\d\d-\d\d$/ )
    {
        $c->response->redirect(
            $c->uri_for( "/admin/topics/list/", { error_msg => 'end_date must be in the form YYYY-MM-DD' } ) );
        return;
    }

    my ( $source_tags_id ) = $c->dbis->query(
        "select t.tags_id from tags t, tag_sets ts " .
          "  where t.tag_sets_id = ts.tag_sets_id " . "    and t.tag = ? and ts.name = 'word_cloud'",
        $source_tag_name
    )->flat;
    if ( !$source_tags_id )
    {
        $c->response->redirect(
            $c->uri_for( "/admin/topics/list/", { error_msg => "source tag '$source_tag_name' not found" } ) );
        return;
    }

    for my $set_tag_name ( split( /[,\s]+/, $set_tag_names ) )
    {
        my ( $tag_set, $tag ) = split( ':', $set_tag_name );
        my $tag_exists = $c->dbis->query(
            "select 1 from tags t, tag_sets ts where t.tag_sets_id = ts.tag_sets_id " . "    and t.tag = ? and ts.name = ?",
            $tag, $tag_set
        )->hash;
        if ( !$tag_exists )
        {
            $c->response->redirect(
                $c->uri_for( "/admin/topics/list/", { error_msg => "set tag $set_tag_name does not exist" } ) );
            return;
        }

    }

    $c->dbis->query(
        "insert into word_cloud_topics " .
          "  (query, type, start_date, end_date, state, url, source_tags_id, set_tag_names, creator) " .
          "  values (?, ?, date_trunc('week', cast(? as date)), " .
          "    date_trunc('week', cast(? as date)) + interval '1 week', ?, ?, ?, ?, ?)",
        $query,
        'words',
        $start_date,
        $end_date,
        'pending',
        $c->uri_for( '/admin/topics/' ),
        $source_tags_id,
        $set_tag_names,
        $creator
    );

    $c->response->redirect( $c->uri_for( "/admin/topics/list/", { status_msg => 'The topic request has been created.' } ) );
}

1;
