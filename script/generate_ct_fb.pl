#!/usr/bin/env perl


use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::TM::Stories;
use MediaWords::Util::Facebook;

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    my $ct_urls = $db->query("select * from scratch.ct_fb where fetched_shares is null")->hashes();

    for my $ct ( @{ $ct_urls } )
    {
        if ( defined( $ct->{ fetched_shares } ) )
        {
            WARN( "EXIST $ct->{ cleaned_url }: $ct->{ shares } / $ct->{ mc_shares } / $ct->{ fetched_shares }" );
            next;
        }   

        my $mc_story;
        if ( $ct->{ stories_id } )
        {
            $mc_story = $db->require_by_id( 'stories', $ct->{ stories_id } );
            $ct->{ cleaned_url } = $mc_story->{ url };
            $db->query(
                'update scratch.ct_fb set cleaned_url = ? where stories_id = ?',
                $mc_story->{ url }, $mc_story->{ stories_id } );
        }
        else
        {
            $mc_story = MediaWords::TM::Stories::get_story_match( $db, $ct->{ cleaned_url } );
        }

        if ( $mc_story && !$ct->{ mc_shares } )
        {
            my $ss = $db->query( 
                "select * from story_statistics where stories_id = ?", $mc_story->{ stories_id } )->hash();
            if ( $ss )
            {
                WARN( "FOUND $ct->{ cleaned_url }: $ct->{ shares } / $ss->{ facebook_share_count }" );
                $db->query(
                    "update scratch.ct_fb set mc_shares = ?, stories_id = ? where cleaned_url = ?",
                    $ss->{ facebook_share_count }, $ss->{ stories_id }, $ct->{ cleaned_url } );
            }
        }

        my ( $shares, $comments, $reactions ) = 
            eval { MediaWords::Util::Facebook::get_url_share_comment_counts( $db, $ct->{ cleaned_url } ) };
        my $ct_shares = $ct->{ shares } || 'null';

        WARN( "FETCH $ct->{ cleaned_url }: $ct_shares / $shares / $reactions" );
        $db->query( <<SQL, $shares, $reactions, $comments, $ct->{ cleaned_url } ); 
update scratch.ct_fb set fetched_shares = ?, fetched_reactions = ?, fetched_comments = ?  where cleaned_url = ?
SQL
    }
}

main()
