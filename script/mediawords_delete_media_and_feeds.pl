#!/usr/bin/env perl

# delete any media or feeds marked with a 'workflow:deletme' tag

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;

sub main
{

    my $db = MediaWords::DB::connect_to_db();

    # do separate select and delete without transactions so that we don't have to lock up the
    # stories table for the whole deletion process
    my ( $delete_tags_id ) =
      $db->query( "select tags_id from tags t, tag_sets ts where t.tag_sets_id = ts.tag_sets_id and " .
          "t.tag = 'deleteme' and ts.name = 'workflow'" )->flat;

    INFO "find shared media stories ...";
    my $update_stories =
      $db->query( "select s.stories_id, s.media_id as from_media_id, f.media_id as to_media_id " .
          "  from stories s, feeds_stories_map fsm, feeds f, media_tags_map mtm_s " .
          "  where s.stories_id = fsm.stories_id and fsm.feeds_id = f.feeds_id " .
          "    and s.media_id = mtm_s.media_id and mtm_s.tags_id = $delete_tags_id " . "    and f.media_id not in (" .
          "      select media_id from media_tags_map where tags_id = $delete_tags_id)" )->hashes;

    for my $story ( @{ $update_stories } )
    {
        INFO "update story $story->{stories_id} set media $story->{from_media_id} -> $story->{to_media_id}";
        $db->query(
            "update stories set media_id = ? where stories_id = ? and guid <> ?",
            $story->{ to_media_id },
            $story->{ stories_id },
            $story->{ guid }
        );
    }

    INFO "find media stories to delete ...";
    my $delete_stories = $db->query(
        "select s.stories_id, s.media_id from stories s, media_tags_map mtm " .
          "  where s.media_id = mtm.media_id and mtm.tags_id = ?",
        $delete_tags_id
    )->hashes;

    INFO "found " . @{ $delete_stories } . " stories to delete";
    my $delete_count = 0;
    for my $story ( @{ $delete_stories } )
    {
        INFO "delete story $story->{stories_id} from media $story->{media_id} [" . ++$delete_count . "]";
        $db->query( "delete from stories where stories_id = ?", $story->{ stories_id } );
    }

    INFO "delete media sources ...";
    $db->query( "delete from media where media_id in (select media_id from media_tags_map mtm where tags_id = ?)",
        $delete_tags_id );

    INFO "find shared feed downlaods ...";
    my $feed_ids = $db->query( "select feeds_id from feeds_tags_map where tags_id = ?", $delete_tags_id )->flat;

    for my $feed_id ( @{ $feed_ids } )
    {
        INFO "process feed $feed_id deletion ...";

        my $downloads = $db->query(
            "select d.downloads_id, d.feeds_id as from_feeds_id, min(fsm.feeds_id) as to_feeds_id " .
              "  from downloads d, feeds_stories_map fsm " .
              "  where d.feeds_id = ? and d.stories_id = fsm.stories_id and fsm.feeds_id <> ? " .
              "  group by d.downloads_id, d.feeds_id",
            $feed_id, $feed_id
        )->hashes;
        for my $download ( @{ $downloads } )
        {
            INFO "update download $download->{downloads_id} " .
              "set feed $download->{from_feeds_id} -> $download->{to_feeds_id}";
            $db->query(
                "update downloads set feeds_id = ? where downloads_id = ?",
                $download->{ to_feeds_id },
                $download->{ downloads_id }
            );
        }

        INFO "find downloads to delete from feed";

        # order by parent so that delete the downloads with parents first to avoid fk constraint
        my $downloads =
          $db->query( "select d.downloads_id from downloads d where d.feeds_id = ? " . "  order by d.parent", $feed_id )
          ->hashes;
        for my $download ( @{ $downloads } )
        {
            INFO "delete download $download->{downloads_id} from feed $feed_id";
            $db->query( "delete from download_texts where downloads_id = ?", $download->{ downloads_id } );
            $db->query( "delete from downloads where downloads_id = ?",      $download->{ downloads_id } );
        }

        INFO "find stories to delete from feed";
        my $stories =
          $db->query( "select s.stories_id, fsma.feeds_id from stories s, feeds_stories_map fsma " .
              "  where s.stories_id = fsma.stories_id and fsma.feeds_id = $feed_id and " .
              "    not exists (" . "      select 1 from feeds_stories_map fsmb " .
              "        where s.stories_id = fsmb.stories_id and fsmb.feeds_id <> $feed_id)" )->hashes;
        for my $story ( @{ $stories } )
        {
            INFO "delete story $story->{stories_id} from feed $feed_id";
            $db->query( "delete from stories where stories_id = ?", $story->{ stories_id } );
        }

        INFO "delete feed $feed_id";
        $db->query( "delete from feeds where feeds_id = ?", $feed_id );
    }

}

main();
