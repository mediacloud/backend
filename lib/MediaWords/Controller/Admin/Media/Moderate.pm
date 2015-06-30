package MediaWords::Controller::Admin::Media::Moderate;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;

use base 'Catalyst::Controller';

use Encode;
use List::Util;
use URI::Split;

use Data::Dumper;
use URI;
use Digest::SHA qw(sha256_hex);

sub index : Path : Args(0)
{
    return media( @_ );
}

# list all media tags and their stats
sub tags : Local
{
    my ( $self, $c ) = @_;

    my $db = $c->dbis;

    my $media_tags = $db->query(
        <<"EOF"
            SELECT
                tag_sets.tag_sets_id,
                tag_sets.name AS tag_sets_name,
                tags.tags_id AS tags_id,
                tags.tag AS tags_name,

                -- number of media sources associated with the tag: total
                COUNT(media_tags_map.media_id) AS count_total,

                -- number of media sources associated with the tag: in moderation queue
                COUNT(
                    CASE WHEN media.moderated = 'f' THEN 1 ELSE NULL END
                ) AS count_unmoderated_total,

                -- number of media sources associated with the tag: not yet processed by RescrapeMedia
                COUNT(
                    CASE WHEN media.moderated = 'f' AND NOT EXISTS (
                        SELECT 1
                        FROM feeds_after_rescraping
                        WHERE feeds_after_rescraping.media_id = media.media_id
                    ) THEN 1 ELSE NULL END
                ) AS count_unmoderated_unprocessed,

                -- number of media sources associated with the tag: in moderation for which there are multiple feeds
                COUNT(
                    CASE WHEN media.moderated = 'f' AND EXISTS (
                        SELECT 1
                        FROM feeds_after_rescraping
                        WHERE feeds_after_rescraping.media_id = media.media_id
                    ) THEN 1 ELSE NULL END
                ) AS count_unmoderated_processed

            FROM tag_sets
                INNER JOIN tags ON tag_sets.tag_sets_id = tags.tag_sets_id
                INNER JOIN media_tags_map ON tags.tags_id = media_tags_map.tags_id

                -- inner join makes sure that only tags with assigned media are shown
                INNER JOIN media ON media_tags_map.media_id = media.media_id

            GROUP BY
                tag_sets.tag_sets_id,
                tag_sets.name,
                tags.tags_id,
                tags.tag

            ORDER BY
                tag_sets.name,
                tags.tag
EOF
    )->hashes;

    $c->stash->{ c }          = $c;
    $c->stash->{ media_tags } = $media_tags;
    $c->stash->{ template }   = 'media/moderate/tags.tt2';
}

# go to the next media source in the moderation queue
sub media : Local
{
    my ( $self, $c, $prev_media_id, $media_sets_id ) = @_;

    my $db = $c->dbis;

    my $approve = $c->request->param( 'approve' );
    my $media_tags_id = $c->request->param( 'media_tags_id' ) || 0;

    $prev_media_id ||= 0;
    if ( $prev_media_id && $approve )
    {
        $db->begin_work;

        $db->query(
            <<EOF,
                UPDATE feeds
                SET feed_status = 'active'
                WHERE feed_status = 'inactive'
                  AND media_id = ?
EOF
            $prev_media_id
        );

        $db->update_by_id( 'media', $prev_media_id, { moderated => 1 } );

        $db->commit;
    }

    my $media_tag;
    if ( $media_tags_id )
    {
        $media_tag = $db->query(
            <<"EOF",
            SELECT
                tag_sets.tag_sets_id,
                tag_sets.name AS tag_sets_name,
                tags.tags_id,
                tags.tag AS tags_name
            FROM tags
                INNER JOIN tag_sets
                    ON tags.tag_sets_id = tag_sets.tag_sets_id
            WHERE tags_id = ?
EOF
            $media_tags_id
        )->hash;
        unless ( $media_tag )
        {
            die "Media tag ID $media_tags_id was not found.";
        }
    }

    # limit by media set or media tag
    my $media_set_clauses = [];
    if ( defined( $media_sets_id ) )
    {
        $media_sets_id += 0;
        push(
            @{ $media_set_clauses },
            "media_id IN ( SELECT media_id FROM media_sets_media_map WHERE media_sets_id = $media_sets_id )"
        );
    }
    if ( $media_tags_id )
    {
        $media_tags_id += 0;
        push( @{ $media_set_clauses },
            "media_id IN ( SELECT media_id FROM media_tags_map WHERE tags_id = $media_tags_id )" );
    }
    if ( scalar( @{ $media_set_clauses } ) > 0 )
    {
        $media_set_clauses = join( ' AND ', @{ $media_set_clauses } );
    }
    else
    {
        $media_set_clauses = '1 = 1';
    }

    my $media = $db->query(
        <<"EOF",
            SELECT *
            FROM media
            WHERE moderated = 'f'
              AND EXISTS (
                SELECT 1
                FROM feeds_after_rescraping
                WHERE feeds_after_rescraping.media_id = media.media_id
              )
              AND media_id > ?
              AND $media_set_clauses
            ORDER BY media_id
EOF
        $prev_media_id
    )->hashes;

    my ( $medium, $tag_names, $feeds, $merge_media );

    if ( @{ $media } )
    {
        $medium    = $media->[ 0 ];
        $tag_names = $db->query(
            <<"EOF",
                SELECT ts.name || ':' || t.tag
                FROM tags t, media_tags_map mtm, tag_sets ts
                WHERE t.tags_id = mtm.tags_id
                  AND t.tag_sets_id = ts.tag_sets_id
                  AND mtm.media_id = ?
EOF
            $medium->{ media_id }
        )->flat;

        $merge_media = $self->_get_potential_merge_media( $c, $medium );

        $#{ $merge_media } = List::Util::min( $#{ $merge_media }, 2 );

        $feeds = _existing_and_rescraped_feeds( $db, $medium->{ media_id } );
    }

    my ( $num_media_pending_feeds ) = $db->query(
        <<EOF
        SELECT COUNT(*)
        FROM media
        WHERE EXISTS (
            SELECT 1
            FROM feeds_after_rescraping
            WHERE feeds_after_rescraping.media_id = media.media_id
          )
          AND moderated = 'f'
EOF
    )->flat;

    $c->stash->{ media_sets_id } = $media_sets_id;
    $c->stash->{ medium }        = $medium;
    $c->stash->{ tag_names }     = $tag_names;
    $c->stash->{ feeds }         = $feeds;
    $c->stash->{ queue_size }    = scalar( @{ $media } );
    $c->stash->{ merge_media }   = $merge_media;
    if ( $media_tags_id )
    {
        $c->stash->{ media_tags_id } = $media_tags_id;
        $c->stash->{ media_tag }     = $media_tag;
    }
    $c->stash->{ num_media_pending_feeds } = $num_media_pending_feeds;
    $c->stash->{ template }                = 'media/moderate/media.tt2';
}

# mark all feeds belonging to this media source as 'skip'
sub skip_feeds : Local
{
    my ( $self, $c, $media_id, $confirm ) = @_;

    my $db = $c->dbis;

    my $media_tags_id = $c->req->params( 'media_tags_id' ) || 0;

    my $medium = $db->query( "select * from media where media_id = ?", $media_id )->hash;

    if ( $medium->{ moderated } )
    {
        my $error = "You can only skip the feeds of media sources that have not yet been moderated";
        $c->response->redirect(
            $c->uri_for(
                "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ),
                { status_msg => $error, media_tags_id => $media_tags_id }
            )
        );
        return;
    }

    if ( defined( $confirm ) )
    {
        my $status_msg;
        if ( $confirm ne 'yes' )
        {
            $status_msg = 'Media source feed skipping cancelled.';
        }
        else
        {
            $db->query( "update feeds set feed_status = 'skipped' where media_id = ?", $media_id );
            $status_msg = 'Media source feeds skipped.';
        }

        $c->response->redirect(
            $c->uri_for(
                "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ),
                { status_msg => $status_msg, media_tags_id => $media_tags_id }
            )
        );
    }
    else
    {
        $c->stash->{ medium }        = $medium;
        $c->stash->{ media_tags_id } = $media_tags_id;
        $c->stash->{ template }      = 'media/moderate/skip_feeds.tt2';
    }
}

# skip the feed without confirmation, but only if it is from an unmoderated media source
sub skip_unmoderated_feed : Local
{
    my ( $self, $c, $feeds_id ) = @_;

    my $db = $c->dbis;

    my $media_tags_id = $c->request->param( 'media_tags_id' ) || 0;

    my $medium = $db->query(
        <<EOF,
        SELECT m.*
        FROM media m, feeds f
        WHERE f.feeds_id = ?
        AND f.media_id = m.media_id
EOF
        $feeds_id
    )->hash;

    if ( $medium->{ moderated } )
    {
        my $error = "You can only skip the feeds of media sources that have not yet been moderated";
        $c->response->redirect(
            $c->uri_for(
                "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ),
                { status_msg => $error, media_tags_id => $media_tags_id }
            )
        );
        return;
    }

    $db->query( "update feeds set feed_status = 'skipped' where feeds_id = ?", $feeds_id );
    my $status_msg = 'Media source feed skipped.';

    $c->response->redirect(
        $c->uri_for(
            "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ),
            { status_msg => $status_msg, media_tags_id => $media_tags_id }
        )
    );
}

# keep only the one feed for the medium
sub keep_single_feed : Local
{
    my ( $self, $c, $feeds_id ) = @_;

    my $db = $c->dbis;

    $feeds_id += 0;

    my $media_tags_id = $c->request->param( 'media_tags_id' ) || 0;

    my $medium =
      $db->query( "select m.* from media m, feeds f where f.feeds_id = ? and f.media_id = m.media_id", $feeds_id )->hash;

    if ( $medium->{ moderated } )
    {
        my $error = "You can only skip the feeds of media sources that have not yet been moderated";
        $c->response->redirect(
            $c->uri_for(
                "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ),
                { status_msg => $error, media_tags_id => $media_tags_id }
            )
        );
        return;
    }

    $db->query(
        "update feeds set feed_status = 'skipped' where media_id = $medium->{ media_id } and feeds_id <> $feeds_id" );
    my $status_msg = 'Media source feeds skipped.';

    if ( $c->req->param( 'approve' ) )
    {
        $c->response->redirect(
            $c->uri_for( "/admin/media/moderate/$medium->{ media_id }", { approve => 1, media_tags_id => $media_tags_id } )
        );
    }
    else
    {
        $c->response->redirect(
            $c->uri_for(
                "/admin/media/moderate/" . ( $medium->{ media_id } - 1 ),
                { status_msg => $status_msg, media_tags_id => $media_tags_id }
            )
        );
    }
}

# merge one media source the tags of medium_a into medium_b and delete medium_b
sub merge : Local
{
    my ( $self, $c, $media_id_a, $media_id_b, $confirm ) = @_;

    my $db = $c->dbis;

    my $media_tags_id = $c->request->param( 'media_tags_id' ) || 0;

    my $medium_a = $db->find_by_id( 'media', $media_id_a );
    my $medium_b = $db->find_by_id( 'media', $media_id_b );

    $confirm ||= 'no';

    if ( !$medium_a->{ moderated } && ( $confirm eq 'yes' ) )
    {
        $self->_merge_media_tags( $c, $medium_a, $medium_b );

        $db->delete_by_id( 'media', $medium_a->{ media_id } );

        $c->response->redirect(
            $c->uri_for( '/admin/media/moderate/' . $medium_a->{ media_id }, { media_tags_id => $media_tags_id } ) );
    }
    else
    {
        my $status_msg;
        if ( $medium_a->{ moderated } )
        {
            $status_msg = "$medium_a->{ name } must not have been moderated to be merged.";
        }

        $c->stash->{ medium_a }      = $medium_a;
        $c->stash->{ medium_b }      = $medium_b;
        $c->stash->{ media_tags_id } = $media_tags_id;
        $c->stash->{ status_msg }    = $status_msg;
        $c->stash->{ template }      = 'media/moderate/merge.tt2';
    }
}

# return any media that might be a candidate for merging with the given media source
sub _get_potential_merge_media
{
    my ( $self, $c, $medium ) = @_;

    my $db = $c->dbis;

    my $host = lc( ( URI::Split::uri_split( $medium->{ url } ) )[ 1 ] );

    my @name_parts = split( /\./, $host );

    my $second_level_domain = $name_parts[ $#name_parts - 1 ];
    if ( ( $second_level_domain eq 'com' ) || ( $second_level_domain eq 'co' ) )
    {
        $second_level_domain = $name_parts[ $#name_parts - 2 ] || 'domainnotfound';
    }

    my $pattern = "%$second_level_domain%";

    return $db->query( "select * from media where ( name like ? or url like ? ) and media_id <> ?",
        $pattern, $pattern, $medium->{ media_id } )->hashes;
}

# merge the tags of medium_a into medium_b
sub _merge_media_tags
{
    my ( $self, $c, $medium_a, $medium_b ) = @_;

    my $db = $c->dbis;

    my $tags_ids = $db->query( "select tags_id from media_tags_map mtm where media_id = ?", $medium_a->{ media_id } )->flat;

    for my $tags_id ( @{ $tags_ids } )
    {
        $db->find_or_create( 'media_tags_map', { media_id => $medium_b->{ media_id }, tags_id => $tags_id } );
    }
}

sub _existing_and_rescraped_feeds($$)
{
    my ( $db, $media_id ) = @_;

    # Calculate a "diff" between existing feeds in "feeds" table and
    # rescraped feeds in "feeds_after_rescraping" table
    my $existing_feeds = $db->query(
        <<EOF,
        SELECT media_id, name, url, feed_type
        FROM feeds
        WHERE media_id = ?
        ORDER BY media_id, name, url, feed_type
EOF
        $media_id
    )->hashes;

    my $rescraped_feeds = $db->query(
        <<EOF,
        SELECT media_id, name, url, feed_type
        FROM feeds_after_rescraping
        WHERE media_id = ?
        ORDER BY media_id, name, url, feed_type
EOF
        $media_id
    )->hashes;

    # Returns unique hash string that can be used to identify a feed
    sub feed_hash($)
    {
        my $feed = shift;

        unless ( $feed->{ media_id } and $feed->{ name } and $feed->{ url } and $feed->{ feed_type } )
        {
            die "Feed hashref is not valid.";
        }

        my $feed_hash_data =
          sprintf( "%s\n%s\n%s\n%s", $feed->{ media_id }, $feed->{ name }, $feed->{ url }, $feed->{ feed_type } );
        my $feed_sha256 = sha256_hex( $feed_hash_data );

        return $feed_sha256;
    }

    sub feed_uniq(@)
    {
        my %h;
        map {
            my $feed_hash = feed_hash( $_ );
            if ( $h{ $feed_hash }++ == 0 )
            {
                $_;
            }
            else
            {
                ();
            }
        } @_;
    }

    my @existing_and_rescraped_feeds = feed_uniq( @{ $existing_feeds }, @{ $rescraped_feeds } );

    # say STDERR "Existing and rescraped feeds: " . Dumper( \@existing_and_rescraped_feeds );
    foreach my $feed ( @existing_and_rescraped_feeds )
    {
        my $feed_hash = feed_hash( $feed );

        my $feed_is_among_existing_feeds = 0;
        foreach my $existing_feed ( @{ $existing_feeds } )
        {
            my $existing_feed_hash = feed_hash( $existing_feed );
            if ( $feed_hash eq $existing_feed_hash )
            {
                $feed_is_among_existing_feeds = 1;
            }
        }

        my $feed_is_among_rescraped_feeds = 0;
        foreach my $rescraped_feed ( @{ $rescraped_feeds } )
        {
            my $rescraped_feed_hash = feed_hash( $rescraped_feed );
            if ( $feed_hash eq $rescraped_feed_hash )
            {
                $feed_is_among_rescraped_feeds = 1;
            }
        }

        my $feed_diff = '';
        if ( $feed_is_among_existing_feeds and $feed_is_among_rescraped_feeds )
        {
            $feed_diff = 'unchanged';
        }
        else
        {
            if ( $feed_is_among_existing_feeds and ( !$feed_is_among_rescraped_feeds ) )
            {
                $feed_diff = 'removed';
            }
            elsif ( ( !$feed_is_among_existing_feeds ) and $feed_is_among_rescraped_feeds )
            {
                $feed_diff = 'added';
            }
            else
            {
                die "Feed is not among existing feeds neither rescraped feeds; probably hashing didn't work.";
            }
        }
        $feed->{ diff } = $feed_diff;
    }

    return \@existing_and_rescraped_feeds;
}

1;
