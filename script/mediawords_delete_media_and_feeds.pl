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

use DBIx::Simple::MediaWords;

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub main
{

    my $db = MediaWords::DB::connect_to_db();

    # do separate select and delete without transactions so that we don't have to lock up the
    # stories table for the whole deletion process
    my ( $delete_tags_id ) =
      $db->query( "select tags_id from tags t, tag_sets ts where t.tag_sets_id = ts.tag_sets_id and " .
          "t.tag = 'deleteme' and ts.name = 'workflow'" )->flat;

    print STDERR "find shared media stories ...\n";
    my $update_stories =
      $db->query( "select s.stories_id, s.media_id as from_media_id, f.media_id as to_media_id " .
          "  from stories s, feeds_stories_map fsm, feeds f, media_tags_map mtm_s " .
          "  where s.stories_id = fsm.stories_id and fsm.feeds_id = f.feeds_id " .
          "    and s.media_id = mtm_s.media_id and mtm_s.tags_id = $delete_tags_id " . "    and f.media_id not in (" .
          "      select media_id from media_tags_map where tags_id = $delete_tags_id)" )->hashes;

    for my $story ( @{ $update_stories } )
    {
        print STDERR "update story $story->{stories_id} set media $story->{from_media_id} -> $story->{to_media_id}\n";
        $db->query(
            "update stories set media_id = ? where stories_id = ? and guid <> ?",
            $story->{ to_media_id },
            $story->{ stories_id },
            $story->{ guid }
        );
    }

    print STDERR "find media stories to delete ...\n";
    my $delete_stories = $db->query(
        "select s.stories_id, s.media_id from stories s, media_tags_map mtm " .
          "  where s.media_id = mtm.media_id and mtm.tags_id = ?",
        $delete_tags_id
    )->hashes;
    print STDERR "found " . @{ $delete_stories } . " stories to delete\n";
    my $delete_count = 0;
    for my $story ( @{ $delete_stories } )
    {
        print STDERR "delete story $story->{stories_id} from media $story->{media_id} [" . ++$delete_count . "]\n";
        $db->query( "delete from stories where stories_id = ?", $story->{ stories_id } );
    }

    print STDERR "delete media sources ...\n";
    $db->query( "delete from media where media_id in (select media_id from media_tags_map mtm where tags_id = ?)",
        $delete_tags_id );

    print STDERR "find shared feed downlaods ...\n";
    my $feed_ids = $db->query( "select feeds_id from feeds_tags_map where tags_id = ?", $delete_tags_id )->flat;

    for my $feed_id ( @{ $feed_ids } )
    {
        print STDERR "process feed $feed_id deletion ...\n";

        my $downloads = $db->query(
            "select d.downloads_id, d.feeds_id as from_feeds_id, min(fsm.feeds_id) as to_feeds_id " .
              "  from downloads d, feeds_stories_map fsm " .
              "  where d.feeds_id = ? and d.stories_id = fsm.stories_id and fsm.feeds_id <> ? " .
              "  group by d.downloads_id, d.feeds_id",
            $feed_id, $feed_id
        )->hashes;
        for my $download ( @{ $downloads } )
        {
            print STDERR "update download $download->{downloads_id} " .
              "set feed $download->{from_feeds_id} -> $download->{to_feeds_id}\n";
            $db->query(
                "update downloads set feeds_id = ? where downloads_id = ?",
                $download->{ to_feeds_id },
                $download->{ downloads_id }
            );
        }

        print STDERR "find downloads to delete from feed\n";

        # order by parent so that delete the downloads with parents first to avoid fk constraint
        my $downloads =
          $db->query( "select d.downloads_id from downloads d where d.feeds_id = ? " . "  order by d.parent", $feed_id )
          ->hashes;
        for my $download ( @{ $downloads } )
        {
            print STDERR "delete download $download->{downloads_id} from feed $feed_id\n";
            $db->query( "delete from download_texts where downloads_id = ?", $download->{ downloads_id } );
            $db->query( "delete from downloads where downloads_id = ?",      $download->{ downloads_id } );
        }

        print STDERR "find stories to delete from feed\n";
        my $stories =
          $db->query( "select s.stories_id, fsma.feeds_id from stories s, feeds_stories_map fsma " .
              "  where s.stories_id = fsma.stories_id and fsma.feeds_id = $feed_id and " .
              "    not exists (" . "      select 1 from feeds_stories_map fsmb " .
              "        where s.stories_id = fsmb.stories_id and fsmb.feeds_id <> $feed_id)" )->hashes;
        for my $story ( @{ $stories } )
        {
            print STDERR "delete story $story->{stories_id} from feed $feed_id\n";
            $db->query( "delete from stories where stories_id = ?", $story->{ stories_id } );
        }

        print STDERR "delete feed $feed_id\n";
        $db->query( "delete from feeds where feeds_id = ?", $feed_id );
    }

}

main();
