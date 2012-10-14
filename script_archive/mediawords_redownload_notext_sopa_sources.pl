#!/usr/bin/env perl

# find sopa story media sources that have lots of stories but no or little text.  Ask the user if
# we should try to redownload each, in the order of the total number of stories

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use strict;

use DateTime;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Web;

# find all media sources with stories in sopa_stories that have 
# an average text length of less than 80
sub get_notext_media
{
    my ( $db ) = @_;
    
    return $db->query( <<END )->hashes;
select m.*, qb.average_story_length, qb.story_count 
    from media m, (
        select media_id, avg( total_story_length )::int average_story_length, count(*) story_count
            from (
                select s.stories_id, min( s.media_id ) media_id, sum( coalesce( dt.download_text_length, 0 ) ) total_story_length
                    from ( select distinct stories_id from sopa_stories ) ss 
                        join stories s on ( s.stories_id = ss.stories_id )
                        left join downloads d on ( s.stories_id = d.stories_id ) 
                        left join download_texts dt on ( d.downloads_id = dt.downloads_id )
                    group by s.stories_id
            ) qa
            group by media_id 
            having avg( total_story_length ) < 80
    ) qb
    where m.media_id = qb.media_id
    order by story_count desc
END
}

# extract the story for the given download
sub extract_download
{
    my ( $db, $download ) = @_;
    
    return if ( $download->{ url } =~ /jpg|pdf|doc|mp3|mp4$/i );
    
    eval {
        MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, "sopa", 1 );
    };
    warn "extract error processing download $download->{ downloads_id }" if ( $@ );
}

# refetch and restore the download, then extract it
sub redownload_download
{
    my ( $db, $download ) = @_;
        
    print "redownloading $download->{ url } [ $download->{ download_text_length } ] ...\n";
    
    my $response = MediaWords::Util::Web::UserAgent->get( $download->{ url } );
    
    if ( !$response->is_success )
    {
        print( "failed to get url: " . $response->request->url . " with error: " . $response->status_line . "\n" );
        return;    
    }
    
    my $story_content = $response->decoded_content;
    
    if ( length( $story_content ) < 1 )
    {
        print( "0 length content\n" );
        return;
    }
    
    $download->{ download_time } = DateTime->now->datetime;
    $db->query( 
        "update downloads set download_time = ? where downloads_id = ?", 
        $download->{ download_time }, $download->{ downloads_id } );
        
    MediaWords::DBI::Downloads::store_content( $db, $download, \$story_content );
    
    extract_download( $db, $download );
    
    my ( $new_length ) = $db->query( 
        "select download_text_length from download_texts where downloads_id = ?",
        $download->{ downloads_id } )->flat;
        
    print "new length: $new_length\n";
    
    return 1;
}

# redownload the content for the story, update the download db entry, and re-extract the download
sub redownload_story
{
    my ( $db, $story ) = @_;
        
    my $downloads_query = <<END;
select d.*, coalesce( dt.download_text_length, 0 ) download_text_length
    from downloads d left join download_texts dt on ( d.downloads_id = dt.downloads_id )
    where d.stories_id = ?
END

    my $downloads = $db->query( $downloads_query, $story->{ stories_id } )->hashes;
    
    map { return unless redownload_download( $db, $_ ) } @{ $downloads };
        
    $db->query( "delete from story_similarities where stories_id_a = ? or stories_id_b = ?", $story->{ stories_id }, $story->{ stories_id } );
    $db->query( "update sopa_stories set link_mined = 'f' where stories_id = ?", $story->{ stories_id } );
}

# ask the user if the medium should be redownloaded.  if so, redownload all of the content for the 
# sopa stories within the medium.
sub fix_notext_medium
{
    my ( $db, $medium ) = @_;
    
    print "fixing medium $medium->{ name } [ $medium->{ media_id } $medium->{ average_story_length } $medium->{ story_count } ] ...\n";
    
    my $query = <<END;
select distinct s.* from stories s, sopa_stories ss
    where s.stories_id = ss.stories_id and s.media_id = $medium->{ media_id }
END
    my $stories = $db->query( $query )->hashes;

    for my $story ( @{ $stories } )
    {
        redownload_story( $db, $story );
    }
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;
    
    my $notext_media = get_notext_media( $db );
    
    map { fix_notext_medium( $db, $_ ) } @{ $notext_media };
}

main();
