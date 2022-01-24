#!/usr/bin/env perl

package MediaWords::TM::Dump;

# dump the stories, story_links, media, and medium_links for a given topic timespan

use strict;
use warnings;

use Encode;
use File::Path;
use File::Slurp;
use Text::CSV_XS;

use MediaWords::CommonLibs;

use MediaWords::DBI::Snapshots;
use MediaWords::TM::Snapshot::ExtraFields;
use MediaWords::TM::Snapshot::Views;
use MediaWords::Util::ParseJSON;
use MediaWords::Util::PublicStore;


# return an encoded csv file representing a list of hashes.
# if $fields is specified, use it as a list of field names and
# snapshot the fields in the specified order.  otherwise, just
# get the field names from the hash in the first row (with
# semi-random order)
sub _get_hashes_as_encoded_csv
{
    my ( $hashes, $fields ) = @_;

    my $output = '';
    if ( @{ $hashes } )
    {
        my $csv = Text::CSV_XS->new( { binary => 1 } );

        my $keys = $fields || [ keys( %{ $hashes->[ 0 ] } ) ];
        $csv->combine( @{ $keys } );

        $output .= $csv->string . "\n";

        for my $hash ( @{ $hashes } )
        {
            $csv->combine( map { $hash->{ $_ } } @{ $keys } );

            $output .= $csv->string . "\n";
        }
    }

    my $encoded_output = Encode::encode( 'utf-8', $output );

    return $encoded_output;
}

# Given a database handle and a query string and some parameters, execute the query with the parameters
# and return the results as a csv with the fields in the query order
sub _get_query_as_csv
{
    my ( $db, $query, @params ) = @_;

    my $res = $db->query( $query, @params );

    my $fields = $res->columns;

    my $data = $res->hashes;

    my $csv_string = _get_hashes_as_encoded_csv( $data, $fields );

    return $csv_string;
}

# Get an encoded csv snapshot of the story links for the given timespan.
sub get_story_links_csv($$)
{
    my ( $db ) = @_;

    my $csv = _get_query_as_csv( $db, "SELECT * FROM snapshot_story_links" );

    return $csv;
}

# Get an encoded csv snapshot of the stories in the given timespan.
sub get_stories_csv($$)
{
    my ( $db, $timespan ) = @_;

    my $res = $db->query( <<SQL
        SELECT
            s.stories_id,
            s.title,
            s.url,
            CASE
                WHEN (stm.tags_id IS NULL) THEN s.publish_date::TEXT
                ELSE 'undateable'
            END AS publish_date,
            m.name AS media_name,
            m.media_id,
            slc.media_inlink_count,
            slc.inlink_count,
            slc.outlink_count,
            slc.facebook_share_count,
            slc.post_count,
            slc.author_count,
            slc.channel_count
        FROM snapshot_stories AS s
            INNER JOIN snapshot_media AS m ON
                s.media_id = m.media_id
            INNER JOIN snapshot_story_link_counts AS slc ON
                s.stories_id = slc.stories_id
            LEFT JOIN (
                snapshot_stories_tags_map AS stm
                    INNER JOIN tags AS t ON
                        stm.tags_id = t.tags_id AND
                        t.tag = 'undateable'
                    INNER JOIN tag_sets AS ts ON
                        t.tag_sets_id = ts.tag_sets_id AND
                        ts.name = 'date_invalid'
            ) ON
                stm.stories_id = s.stories_id
        ORDER BY
            slc.media_inlink_count DESC
SQL
    );

    my $fields = $res->columns;

    my $stories = $res->hashes;

	my $counts = MediaWords::DBI::Snapshots::get_story_counts( $db, $timespan, $stories );

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    my $fields_lookup = {};

    for my $count ( @{ $counts } )
    {
        for my $field ( qw/post_count author_count channel_count/ )
        {
            my $story = $stories_lookup->{ $count->{ stories_id } };
            my $label = "[$count->{ topic_seed_queries_id }] $field";
            $fields_lookup->{ $label } = 1;
            $story->{ $label } = $count->{ $field };
        }
    }

    push( @{ $fields }, sort keys( %{ $fields_lookup } ) );

    my $csv = _get_hashes_as_encoded_csv( $stories, $fields );

    return $csv;
}

# Get an encoded csv snapshot of the medium_links in the given timespan.
sub get_medium_links_csv($$)
{
    my ( $db, $timespan ) = @_;

    my $csv = _get_query_as_csv( $db, "SELECT * FROM snapshot_medium_links" );

    return $csv;
}

# Get an encoded csv snapshot of the media in the given timespan.
sub get_media_csv($$)
{
    my ( $db, $timespan ) = @_;

    my $res = $db->query( <<SQL );
        SELECT
            m.name,
            m.url,
            mlc.*
        FROM
            snapshot_media AS m,
            snapshot_medium_link_counts AS mlc
        WHERE m.media_id = mlc.media_id
        ORDER BY mlc.media_inlink_count DESC
SQL

    my $fields = $res->columns;
    my $media  = $res->hashes;

    my $extra_fields = MediaWords::TM::Snapshot::ExtraFields::add_extra_fields_to_snapshot_media( $db, $timespan, $media );

    push( @{ $fields }, @{ $extra_fields } );

	my $counts = MediaWords::DBI::Snapshots::get_medium_counts( $db, $timespan, $media );

    my $media_lookup = {};
    map { $media_lookup->{ $_->{ media_id } } = $_ } @{ $media };

    my $fields_lookup = {};

    for my $count ( @{ $counts } )
    {
        for my $field ( qw/sum_post_count sum_author_count sum_channel_count/ )
        {
            my $medium = $media_lookup->{ $count->{ media_id } };
            my $label = "[$count->{ topic_seed_queries_id }] $field";
            $fields_lookup->{ $label } = 1;
            $medium->{ $label } = $count->{ $field };
        }
    }

    push( @{ $fields }, sort keys( %{ $fields_lookup } ) );

    my $csv = _get_hashes_as_encoded_csv( $media, $fields );

    return $csv;
}

# get the metadata only for topic posts within the current timespan
sub get_topic_posts_csv($$)
{
    my ( $db, $timespan ) = @_;

    my $csv = _get_query_as_csv( $db, <<SQL
        SELECT
            tpd.topic_seed_queries_id,
            tp.topic_posts_id,
            tp.publish_date,
            tp.author,
            tp.channel,
            tp.url
        FROM topic_post_days AS tpd
            INNER JOIN topic_posts AS tp ON
                tpd.topics_id = tp.topics_id AND
                tpd.topic_post_days_id = tp.topic_post_days_id
    		INNER JOIN snapshot_timespan_posts ON
                tp.topics_id = snapshot_timespan_posts.topics_id AND
                tp.topic_posts_id = snapshot_timespan_posts.topic_posts_id
SQL
    );

    return $csv;
}

sub get_post_stories_csv($$)
{
    my ( $db, $timespan ) = @_;

    my $csv = _get_query_as_csv( $db, <<SQL
        SELECT DISTINCT
            snapshot_timespan_posts.topic_posts_id,
            snapshot_topic_post_stories.stories_id
        FROM snapshot_timespan_posts
            INNER JOIN snapshot_topic_post_stories ON
                snapshot_timespan_posts.topics_id = snapshot_topic_post_stories.topics_id AND
                snapshot_timespan_posts.topic_posts_id = snapshot_topic_post_stories.topic_posts_id
SQL
    );

    return $csv;
}


# get the object_id with which to store the file
sub get_store_object_id
{
    my ( $id, $name ) = @_;

    return "$id-$name";
}


sub store_timespan_file($$$$)
{
    my ( $db, $timespan, $name, $content ) = @_;

    my $object_id = get_store_object_id( $timespan->{ timespans_id }, $name );
    my $object_type = 'timespan_files';

    MediaWords::Util::PublicStore::store_content( $db, $object_type, $object_id, $content, 'text/csv' );

    my $url = MediaWords::Util::PublicStore::get_content_url( $db, $object_type, $object_id );

    $db->query( <<SQL,
        INSERT INTO timespan_files (topics_id, timespans_id, name, url)
        VALUES (?, ?, ?, ?)
        ON CONFLICT (topics_id, timespans_id, name) DO UPDATE SET
            url = EXCLUDED.url
SQL
        $timespan->{ topics_id }, $timespan->{ timespans_id }, $name, $url
    );
}

# generate various dumps for a single timespan and store them in s3, with the public urls
# stored in timespan_files
sub dump_timespan($$)
{
    my ( $db, $timespan ) = @_;

    DEBUG( "dumping stories ..." );
    my $stories_csv = get_stories_csv( $db, $timespan );
    store_timespan_file( $db, $timespan, "stories", $stories_csv );

    DEBUG( "dumping media ..." );
    my $media_csv = get_media_csv( $db, $timespan );
    store_timespan_file( $db, $timespan, "media", $media_csv );

    DEBUG( "dumping story links ..." );
    my $story_links_csv = get_story_links_csv( $db, $timespan );
    store_timespan_file( $db, $timespan, "story_links", $story_links_csv );
 
    DEBUG( "dumping medium_links ..." );
    my $medium_links_csv = get_medium_links_csv( $db, $timespan );
    store_timespan_file( $db, $timespan, "medium_links", $medium_links_csv );

    DEBUG ( "dump topic posts ...");
    my $topic_posts_csv = get_topic_posts_csv( $db, $timespan );
    store_timespan_file( $db, $timespan, "topic_posts", $topic_posts_csv );

    DEBUG ( "dump topic post stories ...");
    my $topic_post_stories_csv = get_post_stories_csv( $db, $timespan );
    store_timespan_file( $db, $timespan, "post_stories", $topic_post_stories_csv );
}

sub get_topic_posts_ndjson
{
    my ( $db, $snapshot ) = @_;

    $db->begin;

    $db->query( <<SQL,
        DECLARE posts CURSOR FOR
            WITH _snapshot_posts AS (
                SELECT DISTINCT
                    stp.topics_id,
                    topic_posts_id
                FROM snap.timespan_posts AS stp
                    INNER JOIN timespans AS t ON
                        stp.topics_id = t.topics_id AND
                        stp.timespans_id = t.timespans_id
                WHERE
                    stp.topics_id = ? AND
                    t.snapshots_id = ?
            )

            SELECT
                tp.*,
                tpd.topic_seed_queries_id
            FROM topic_posts AS tp
                INNER JOIN topic_post_days AS tpd ON
                    tp.topics_id = tpd.topics_id AND
                    tp.topic_post_days_id = tpd.topic_post_days_id
                INNER JOIN _snapshot_posts AS sp ON
                    tp.topics_id = sp.topics_id AND
                    tp.topic_posts_id = sp.topic_posts_id
SQL
        $snapshot->{ topics_id }, $snapshot->{ snapshots_id }
    );

    my $ndjson = '';
    while ( 1 )
    {
        my $posts = $db->query( "fetch 1000 from posts" )->hashes();

        last unless ( @{ $posts } );

        $ndjson .= join( '',map { MediaWords::Util::ParseJSON::encode_json( $_ ) . "\n" } @{ $posts } );
    }

    $db->commit;

    return $ndjson;
}

sub store_snapshot_file($$$$)
{
    my ( $db, $snapshot, $name, $content ) = @_;

    my $object_id = get_store_object_id( $snapshot->{ snapshots_id }, $name );
    my $object_type = 'snapshot_files';

    MediaWords::Util::PublicStore::store_content( $db, $object_type, $object_id, $content, 'application/x-ndjson' );

    my $url = MediaWords::Util::PublicStore::get_content_url( $db, $object_type, $object_id );

    $db->query( <<SQL,
        INSERT INTO snapshot_files (topics_id, snapshots_id, name, url)
        VALUES (?, ?, ?, ?)
        ON CONFLICT (topics_id, snapshots_id, name) DO UPDATE SET
            url = EXCLUDED.url
SQL
        $snapshot->{ topics_id }, $snapshot->{ snapshots_id }, $name, $url
    );

}

# generate dumps at the snapshot level and store then in s3, with the public urls stored in snapshot_files
sub dump_snapshot($$)
{
    my  ( $db, $snapshot ) = @_;

    my $topic_posts_json = get_topic_posts_ndjson( $db, $snapshot );
    store_snapshot_file( $db, $snapshot, 'topic_posts', $topic_posts_json );
}

1;
