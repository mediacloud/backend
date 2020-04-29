#!/usr/bin/env perl

# dump the stories, story_links, media, and medium_links for a given topic timespan

use strict;
use warnings;

use MediaWords::CommonLibs;

use Data::Dumper;
use File::Slurp;

use MediaWords::TM::Dump;
use MediaWords::TM::Snapshot::ExtraFields;
use MediaWords::TM::Snapshot::Views;
use MediaWords::DB;

# Get an encoded csv snapshot of the story links for the given timespan.
sub _get_story_links_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::TM::Dump::_get_query_as_csv( $db, <<END );
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

    my $res = $db->query( <<END );
select s.stories_id, s.title, s.url,
        case when ( stm.tags_id is null ) then s.publish_date::text else 'undateable' end as publish_date,
        m.name media_name, m.url media_url, m.media_id,
        slc.media_inlink_count, slc.inlink_count, slc.outlink_count, slc.facebook_share_count,
        slc.post_count
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

	my $story_post_counts = $db->query( <<END, $timespan->{ timespans_id } )->hashes;
with counts as (
    select 
            count(*) post_count, ts.stories_id, tsu.topic_seed_queries_id 
        from snapshot_stories ts 
            join topic_seed_urls tsu using ( stories_id ) 
            join topic_post_days tpd using ( topic_seed_queries_id )
            join timespans t using ( snapshots_id )
            join snapshots s using ( snapshots_id )
        where 
            s.topics_id = tsu.topics_id and
            t.timespans_id = ? and
            ( 
                ( period = 'overall' ) or
                ( tpd.day between t.start_date and t.end_date )
            )
        group by stories_id, topic_seed_queries_id 
) 

select *
    from counts c 
        join topic_seed_queries tsq using ( topic_seed_queries_id);
END

    my $stories_lookup = {};
    map { $stories_lookup->{ $_->{ stories_id } } = $_ } @{ $stories };

    my $fields_lookup = {};

    for my $spc ( @{ $story_post_counts } )
    {
        my $story = $stories_lookup->{ $spc->{ stories_id } };
        my $label = "$spc->{ platform }_$spc->{ source }_$spc->{ topic_seed_queries_id }";
        $fields_lookup->{ $label } = 1;
        $story->{ $label } = $spc->{ post_count };
    }

    push( @{ $fields }, keys( %{ $fields_lookup } ) );

    my $csv = MediaWords::TM::Dump::_get_hashes_as_encoded_csv( $stories, $fields );

    return $csv;
}

# Get an encoded csv snapshot of the medium_links in the given timespan.
sub _get_medium_links_csv
{
    my ( $db, $timespan ) = @_;

    my $csv = MediaWords::TM::Dump::_get_query_as_csv( $db, <<END );
select ml.source_media_id, sm.name source_name, sm.url source_url,
        ml.ref_media_id, rm.name ref_name, rm.url ref_url, ml.link_count
    from snapshot_medium_links ml, media sm, media rm
    where ml.source_media_id = sm.media_id and ml.ref_media_id = rm.media_id
END

    return $csv;
}

# Get an encoded csv snapshot of the media in the given timespan.
sub _get_media_csv
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

    my $csv = MediaWords::TM::Dump::_get_hashes_as_encoded_csv( $media, $fields );

    return $csv;
}

sub main
{
    my ( $timespans_id ) = @ARGV;

    die( "usage: $0 <timespans_id>" ) unless ( $timespans_id );

    my $db = MediaWords::DB::connect_to_db();

    my $timespan = $db->find_by_id( "timespans", $timespans_id )
      || die( "no timespan found for $timespans_id" );

    DEBUG( "setting up snapshot ..." );
    MediaWords::TM::Snapshot::Views::setup_temporary_snapshot_views( $db, $timespan );

    DEBUG( "dumping stories ..." );
    my $stories_csv = _get_stories_csv( $db, $timespan );
    write_file( "stories_${ timespans_id }.csv", \$stories_csv );

    DEBUG( "dumping media ..." );
    my $media_csv = _get_media_csv( $db, $timespan );
    write_file( "media_${ timespans_id }.csv", \$media_csv );

    # DEBUG( "dumping story links ..." );
    # my $story_links_csv = _get_story_links_csv( $db, $timespan );
    # write_file( "story_links_${ timespans_id }.csv", \$story_links_csv );

    DEBUG( "dumping medium_links ..." );
    my $medium_links_csv = _get_medium_links_csv( $db, $timespan );
    write_file( "medium_links_${ timespans_id }.csv", \$medium_links_csv );

    DEBUG( "dumping medium_tags ..." );
    my $medium_tags_csv = MediaWords::TM::Dump::_get_query_as_csv( $db, <<SQL );
select mtm.media_id, t.tags_id, t.tag, t.label, t.tag_sets_id, ts.name tag_set_name
    from snapshot_medium_link_counts mlc
        join snapshot_media_tags_map mtm using ( media_id )
        join tags t using ( tags_id )
        join tag_sets ts using ( tag_sets_id )
SQL
    write_file( "medium_tags_${ timespans_id }.csv", \$medium_tags_csv );
}

main();
