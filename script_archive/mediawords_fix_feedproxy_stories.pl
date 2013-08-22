#!/usr/bin/env perl

# change feed proxy stories in trayvon controversy to point to redirected url

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use LWP;

use MediaWords::CM::Mine;
use MediaWords::DB;
use MediaWords::Util::Web;

sub main
{

    my $db = MediaWords::DB::connect_to_db();

    my $controversy = $db->query( "select * from controversies where controversies_id = 1" )->hash;

    my $old_stories = $db->query( <<END )->hashes;
select s.* 
    from stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id )
        join media m on ( s.media_id = m.media_id )
    where 
        cs.controversies_id = 1 and
        m.name = 'feedproxy.google.com'
END

    MediaWords::Util::Web::cache_link_downloads( $old_stories );
    MediaWords::CM::Mine::add_redirect_links( $db, $old_stories );

    for my $old_story ( @{ $old_stories } )
    {
        my $new_story =
             MediaWords::CM::Mine::get_matching_story_from_db( $db, { url => $old_story->{ redirect_url } }, $controversy )
          || MediaWords::CM::Mine::add_new_story( $db, $old_story, undef, $controversy );

        MediaWords::CM::Mine::merge_dup_story( $db, $controversy, $old_story, $new_story );
    }
}

main();
