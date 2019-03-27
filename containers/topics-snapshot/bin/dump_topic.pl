#!/usr/bin/env perl

# dump the stories, story_links, media, and medium_links for a given topic timespan

use strict;
use warnings;

use MediaWords::CommonLibs;

use Data::Dumper;
use File::Slurp;

use MediaWords::TM::Snapshot;
use MediaWords::DB;
use MediaWords::Util::CSV;

# Get an encoded csv snapshot of the story links for the given timespan.
sub _get_story_links_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<END );
select distinct sl.source_stories_id source_stories_id, ss.title source_title, ss.url source_url,
        sm.name source_media_name, sm.url source_media_url, sm.media_id source_media_id,
        sl.ref_stories_id ref_stories_id, rs.title ref_title, rs.url ref_url, rm.name ref_media_name, rm.url ref_media_url,
        rm.media_id ref_media_id
    from snapshot_story_links sl, snap.live_stories ss, media sm, snap.live_stories rs, media rm
    where sl.source_stories_id = ss.stories_id and
        ss.media_id = sm.media_id and
        sl.ref_stories_id = rs.stories_id and
        rs.media_id = rm.media_id
END

    return $csv;
}

# Get an encoded csv snapshot of the stories inr the given timespan.
sub _get_stories_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<END );
select s.stories_id, s.title, s.url,
        case when ( stm.tags_id is null ) then s.publish_date::text else 'undateable' end as publish_date,
        m.name media_name, m.url media_url, m.media_id,
        slc.media_inlink_count, slc.inlink_count, slc.outlink_count, slc.facebook_share_count,
        slc.simple_tweet_count, slc.normalized_tweet_count
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

    return $csv;
}

# Get an encoded csv snapshot of the medium_links in the given timespan.
sub get_medium_links_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<END );
select ml.source_media_id, sm.name source_name, sm.url source_url,
        ml.ref_media_id, rm.name ref_name, rm.url ref_url, ml.link_count
    from snapshot_medium_links ml, media sm, media rm
    where ml.source_media_id = sm.media_id and ml.ref_media_id = rm.media_id
END

    return $csv;
}

sub main
{
    my ( $timespans_id ) = @ARGV;

    die( "usage: $0 <timespans_id>" ) unless ( $timespans_id );

    my $db = MediaWords::DB::connect_to_db;

    my $timespan = $db->find_by_id( "timespans", $timespans_id )
      || die( "no timespan found for $timespans_id" );

    DEBUG( "setting up snapshot ..." );
    MediaWords::TM::Snapshot::setup_temporary_snapshot_views( $db, $timespan );

    DEBUG( "dumping stories ..." );
    my $stories_csv = _get_stories_csv( $db, $timespan );
    File::Slurp::write_file( "stories_${ timespans_id }.csv", \$stories_csv );

    DEBUG( "dumping media ..." );
    my $media_csv = MediaWords::TM::Snapshot::get_media_csv( $db, $timespan );
    File::Slurp::write_file( "media_${ timespans_id }.csv", \$media_csv );

    DEBUG( "dumping story links ..." );
    my $story_links_csv = _get_story_links_csv( $db, $timespan );
    File::Slurp::write_file( "story_links_${ timespans_id }.csv", \$story_links_csv );

    DEBUG( "dumping medium_links ..." );
    my $medium_links_csv = _get_medium_links_csv( $db, $timespan );
    File::Slurp::write_file( "medium_links_${ timespans_id }.csv", \$medium_links_csv );

    DEBUG( "dumping medium_tags ..." );
    my $medium_tags_csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<SQL );
select mtm.media_id, t.tags_id, t.tag, t.label, t.tag_sets_id, ts.name tag_set_name
    from snapshot_medium_link_counts mlc
        join snapshot_media_tags_map mtm using ( media_id )
        join snapshot_tags t using ( tags_id )
        join snapshot_tag_sets ts using ( tag_sets_id )
SQL
    File::Slurp::write_file( "medium_tags_${ timespans_id }.csv", \$medium_tags_csv );

}

main();
