package MediaWords::Controller::Topics;
use Modern::Perl "2012";
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

    my $topics = $c->dbis->query(
        <<EOF
        SELECT w.*,
               t.tag AS source_tag_name
        FROM word_cloud_topics AS w
            LEFT JOIN tags AS t ON w.source_tags_id = t.tags_id
        WHERE w.type = 'words'
        ORDER BY w.word_cloud_topics_id
EOF
    )->hashes;

    $c->stash->{ topics }   = $topics;
    $c->stash->{ template } = 'topics/list.tt2';
}

# create a new topic
sub create_do : Local
{
    my ( $self, $c ) = @_;

    my $query           = $c->request->param( 'query' );
    my $language_code   = $c->request->param( 'language' );
    my $start_date      = $c->request->param( 'start_date' );
    my $end_date        = $c->request->param( 'end_date' );
    my $source_tag_name = $c->request->param( 'source_tag_name' );
    my $set_tag_names   = $c->request->param( 'set_tag_names' );
    my $creator         = $c->request->param( 'creator' );

    if ( !( $query && $language && $start_date && $end_date && $source_tag_name && $set_tag_names && $creator ) )
    {
        my $msg = 'query, language, start_date, end_date, source_tag_name, set_tag_names, and creator are all required.';
        $c->response->redirect( $c->uri_for( "/topics/list/", { error_msg => $msg } ) );
        return;
    }

    if ( $start_date !~ /^\d\d\d\d-\d\d-\d\d$/ )
    {
        $c->response->redirect(
            $c->uri_for( "/topics/list/", { error_msg => 'start_date must be in the form YYYY-MM-DD' } ) );
        return;
    }

    if ( $end_date !~ /^\d\d\d\d-\d\d-\d\d$/ )
    {
        $c->response->redirect( $c->uri_for( "/topics/list/", { error_msg => 'end_date must be in the form YYYY-MM-DD' } ) );
        return;
    }

    my ( $source_tags_id ) = $c->dbis->query(
        <<EOF,
        SELECT t.tags_id
        FROM tags AS t,
             tag_sets AS ts
        WHERE t.tag_sets_id = ts.tag_sets_id
              AND t.tag = ?
              AND ts.name = 'word_cloud'
EOF
        $source_tag_name
    )->flat;
    if ( !$source_tags_id )
    {
        $c->response->redirect( $c->uri_for( "/topics/list/", { error_msg => "source tag '$source_tag_name' not found" } ) );
        return;
    }

    for my $set_tag_name ( split( /[,\s]+/, $set_tag_names ) )
    {
        my ( $tag_set, $tag ) = split( ':', $set_tag_name );
        my $tag_exists = $c->dbis->query(
            <<EOF,
            SELECT 1
            FROM tags AS t,
                 tag_sets AS ts
            WHERE t.tag_sets_id = ts.tag_sets_id
                  AND t.tag = ?
                  AND ts.name = ?
EOF
            $tag, $tag_set
        )->hash;
        if ( !$tag_exists )
        {
            $c->response->redirect(
                $c->uri_for( "/topics/list/", { error_msg => "set tag $set_tag_name does not exist" } ) );
            return;
        }

    }

    $c->dbis->query(
        <<EOF,
        INSERT INTO word_cloud_topics (
            query,
            language,
            type,
            start_date,
            end_date,
            state,
            url,
            source_tags_id,
            set_tag_names,
            creator
        ) VALUES (
            ?,
            ?,
            ?,
            DATE_TRUNC('week', CAST(? AS DATE)),
            DATE_TRUNC('week', CAST(? AS DATE)) + INTERVAL '1 week',
            ?,
            ?,
            ?,
            ?,
            ?
        )
EOF
        $query,
        $language,
        'words',
        $start_date,
        $end_date,
        'pending',
        $c->uri_for( '/topics/' ),
        $source_tags_id,
        $set_tag_names,
        $creator
    );

    $c->response->redirect( $c->uri_for( "/topics/list/", { status_msg => 'The topic request has been created.' } ) );
}

1;
