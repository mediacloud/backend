#!/usr/bin/env perl

# dump the stories, story_links, media, and medium_links for a given topic timespan

use strict;
use warnings;

use MediaWords::CommonLibs;

use Data::Dumper;
use File::Slurp;

use MediaWords::TM::Snapshot;
use MediaWords::DB;

sub main
{
    my ( $timespans_id ) = @ARGV;

    die( "usage: $0 <timespans_id>" ) unless ( $timespans_id );

    my $db = MediaWords::DB::connect_to_db;

    my $timespan = $db->find_by_id( "timespans", $timespans_id )
      || die( "no timespan found for $timespans_id" );

    DEBUG( "setting up snapshot ..." );
    MediaWords::TM::Snapshot::create_temporary_snapshot_views( $db, $timespan );

    DEBUG( "dumping stories ..." );
    my $stories_csv = MediaWords::TM::Snapshot::get_stories_csv( $db, $timespan );
    File::Slurp::write_file( "stories_${ timespans_id }.csv", \$stories_csv );

    DEBUG( "dumping media ..." );
    my $media_csv = MediaWords::TM::Snapshot::get_media_csv( $db, $timespan );
    File::Slurp::write_file( "media_${ timespans_id }.csv", \$media_csv );

    DEBUG( "dumping story links ..." );
    my $story_links_csv = MediaWords::TM::Snapshot::get_story_links_csv( $db, $timespan );
    File::Slurp::write_file( "story_links_${ timespans_id }.csv", \$story_links_csv );

    DEBUG( "dumping medium_links ..." );
    my $medium_links_csv = MediaWords::TM::Snapshot::get_medium_links_csv( $db, $timespan );
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
