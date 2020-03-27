#!/usr/bin/env perl

package MediaWords::TM::Dump;

# dump the stories, story_links, media, and medium_links for a given topic timespan

use strict;
use warnings;

use File::Path;
use File::Slurp;

use MediaWords::CommonLibs;

use MediaWords::DBI::Snapshots;
use MediaWords::TM::Snapshot::ExtraFields;
use MediaWords::TM::Snapshot::Views;
use MediaWords::Util::CSV;
use MediaWords::Util::PublicS3Store;

# Get an encoded csv snapshot of the story links for the given timespan.
sub get_story_links_csv($$)
{
    my ( $db ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, "select * from snapshot_story_links" );

    return $csv;
}

# Get an encoded csv snapshot of the stories in the given timespan.
sub get_stories_csv($$)
{
    my ( $db, $timespan ) = @_;

    my $res = $db->query( <<END );
select s.stories_id, s.title, s.url,
        case when ( stm.tags_id is null ) then s.publish_date::text else 'undateable' end as publish_date,
        m.name media_name, m.media_id,
        slc.media_inlink_count, slc.inlink_count, slc.outlink_count, slc.facebook_share_count,
        slc.post_count, slc.author_count, slc.channel_count
    from snapshot_stories s
        join snapshot_media m on ( s.media_id = m.media_id )
        join snapshot_story_link_counts slc on ( s.stories_id = slc.stories_id )
        left join (
            snapshot_stories_tags_map stm
                join tags t on ( stm.tags_id = t.tags_id  and t.tag = 'undateable' )
                join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id and ts.name = 'date_invalid' ) )
            on ( stm.stories_id = s.stories_id )
    order by slc.media_inlink_count desc
END

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

    my $csv = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $stories, $fields );

    return $csv;
}

# Get an encoded csv snapshot of the medium_links in the given timespan.
sub get_medium_links_csv($$)
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, "select * from snapshot_medium_links" );

    return $csv;
}

# Get an encoded csv snapshot of the media in the given timespan.
sub get_media_csv($$)
{
    my ( $db, $timespan ) = @_;

    my $res = $db->query( <<END );
select m.name, m.url, mlc.*
    from snapshot_media m, snapshot_medium_link_counts mlc
    where m.media_id = mlc.media_id
    order by mlc.media_inlink_count desc;
END

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

    my $csv = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $media, $fields );

    return $csv;
}

# get the metadata only for topic posts within the current timespan
sub get_topic_posts_csv($$)
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<SQL );
select 
        tpd.topic_seed_queries_id, tp.topic_posts_id, tp.publish_date, tp.author, tp.channel, tp.url
    from topic_post_days tpd
        join topic_posts tp using ( topic_post_days_id )
		join snapshot_timespan_posts using ( topic_posts_id )
SQL

    return $csv;
}

sub get_post_stories_csv($$)
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<SQL );
select distinct topic_posts_id, stories_id from snapshot_timespan_posts join topic_post_stories using ( topic_posts_id )
SQL

    return $csv;
}


sub store_file($$$$)
{
    my ( $db, $timespan, $name, $content ) = @_;

    my $object_id = "$timespan->{ timespans_id }-$name";
    my $object_type = $MediaWords::Util::PublicS3Store::TIMESPAN_FILES_TYPE;

    MediaWords::Util::PublicS3Store::store_content( $db, $object_type, $object_id, $content, 'text/csv' );

    my $url = MediaWords::Util::PublicS3Store::get_content_url( $db, $object_type, $object_id );

    $db->query( <<SQL, $timespan->{ timespans_id }, $name, $url );
insert into timespan_files ( timespans_id, name, url )
    values ( ?, ?, ? )
    on conflict ( timespans_id, name ) do update set
        url = excluded.url
SQL

}

# generate various dumps for a single timespan and store them in s3, with the public urls
# stored in timespan_files
sub dump_timespan($$)
{
    my ( $db, $timespan ) = @_;

    DEBUG( "setting up snapshot ..." );
    MediaWords::TM::Snapshot::Views::setup_temporary_snapshot_views( $db, $timespan );

    DEBUG( "dumping stories ..." );
    my $stories_csv = get_stories_csv( $db, $timespan );
    store_file( $db, $timespan, "stories", $stories_csv );

    DEBUG( "dumping media ..." );
    my $media_csv = get_media_csv( $db, $timespan );
    store_file( $db, $timespan, "media", $media_csv );

    DEBUG( "dumping story links ..." );
    my $story_links_csv = get_story_links_csv( $db, $timespan );
    store_file( $db, $timespan, "story_links", $story_links_csv );
 
    DEBUG( "dumping medium_links ..." );
    my $medium_links_csv = get_medium_links_csv( $db, $timespan );
    store_file( $db, $timespan, "medium_links", $medium_links_csv );

    DEBUG ( "dump topic posts ...");
    my $topic_posts_csv = get_topic_posts_csv( $db, $timespan );
    store_file( $db, $timespan, "topic_posts", $topic_posts_csv );

    DEBUG ( "dump topic post stories ...");
    my $topic_post_stories_csv = get_post_stories_csv( $db, $timespan );
    store_file( $db, $timespan, "post_stories", $topic_post_stories_csv );

    $db->query( "discard temp" );
}

1;
