#!/usr/bin/env perl

#
# for a given topic, parse the content for any youtube embed links and
# insert them as links in topic_links
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";

use Encode;
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::TM::Mine;

sub extract_links_for_story
{
    my ( $db, $story, $topic ) = @_;

    my $youtube_links = MediaWords::TM::Mine::get_youtube_embed_links( $db, $story );

    if ( !@{ $youtube_links } )
    {
        print STDERR '.';
        return;
    }

    say STDERR "\n[ $story->{ stories_id } ] $story->{ url }";
    for my $link ( @{ $youtube_links } )
    {
        next if ( $link->{ url } eq $story->{ url } );

        my $link_exists = $db->query(
            "select * from topic_links where stories_id = ? and url = ? and topics_id = ?",
            $story->{ stories_id },
            encode( 'utf8', $link->{ url } ),
            $topic->{ topics_id }
        )->hash;

        if ( $link_exists )
        {
            print STDERR "    -> dup: $link->{ url }\n";
        }
        else
        {
            print STDERR "    -> new: $link->{ url }\n";
            $db->create(
                "topic_links",
                {
                    stories_id => $story->{ stories_id },
                    url        => encode( 'utf8', $link->{ url } ),
                    topics_id  => $topic->{ topics_id }
                }
            );
        }
    }
}

sub main
{
    my ( $arg ) = @ARGV;

    die( "usage: $0 < topic_name >" ) unless ( $arg );

    my $db = MediaWords::DB::connect_to_db;

    my $topic = $db->query( "select * from topics where name = ?", $arg )->hash
      || die( "no topic found for '$arg'" );

    my $stories = $db->query( <<END, $topic->{ topics_id } )->hashes;
select s.stories_id, s.url
    from snap.live_stories s
        join topic_stories cs on ( cs.stories_id = s.stories_id )
    where
        cs.topics_id = ?
	order by stories_id
END

    if ( !@{ $stories } )
    {
        say STDERR "No stories found for topic '$topic->{ name }'";
    }

    map { extract_links_for_story( $db, $_, $topic ) } @{ $stories };
}

main();
