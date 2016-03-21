#!/usr/bin/env perl

#
# for a given controversy, parse the content for any youtube embed links and
# insert them as links in controversy_links
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
use MediaWords::CM::Mine;

sub extract_links_for_story
{
    my ( $db, $story, $controversy ) = @_;

    my $youtube_links = MediaWords::CM::Mine::get_youtube_embed_links( $db, $story );

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
            "select * from controversy_links where stories_id = ? and url = ? and controversies_id = ?",
            $story->{ stories_id },
            encode( 'utf8', $link->{ url } ),
            $controversy->{ controversies_id }
        )->hash;

        if ( $link_exists )
        {
            print STDERR "    -> dup: $link->{ url }\n";
        }
        else
        {
            print STDERR "    -> new: $link->{ url }\n";
            $db->create(
                "controversy_links",
                {
                    stories_id       => $story->{ stories_id },
                    url              => encode( 'utf8', $link->{ url } ),
                    controversies_id => $controversy->{ controversies_id }
                }
            );
        }
    }
}

sub main
{
    my ( $arg ) = @ARGV;

    die( "usage: $0 < controversy_name >" ) unless ( $arg );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->query( "select * from controversies where name = ?", $arg )->hash
      || die( "no controversy found for '$arg'" );

    my $stories = $db->query( <<END, $controversy->{ controversies_id } )->hashes;
select s.stories_id, s.url
    from cd.live_stories s
        join controversy_stories cs on ( cs.stories_id = s.stories_id )
    where
        cs.controversies_id = ?
	order by stories_id
END

    if ( !@{ $stories } )
    {
        say STDERR "No stories found for controversy '$controversy->{ name }'";
    }

    map { extract_links_for_story( $db, $_, $controversy ) } @{ $stories };
}

main();
