#!/usr/bin/perl

# dedup sopa spidered media sources

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Util::Tags;

# get the domain from the medium url
sub get_medium_domain
{
    my ( $medium ) = @_;
    
    $medium->{ url } =~ m~https?://([^/]*)~ || return $medium;
    
    my $host = $1;
    
    my $name_parts = [ split( /\./, $host ) ];
    
    my $n = @{ $name_parts } - 1;
    
    if ( $host =~ /\.co.uk$/ )
    {
        return join( ".", ( $name_parts->[ $n-2 ], $name_parts->[ $n-1 ], $name_parts->[ $n ] ) );
    }
    
    return join( ".", $name_parts->[ $n-1 ], $name_parts->[ $n ] );
}

# search for stories with duplicate guids in the media and delete them manually to avoid guid conflicts
sub dedup_stories
{
    my ( $db, $target_medium, $source_medium ) = @_;
    
    my $dup_stories = $db->query( 
        "select d.* from stories d " . 
        "  where d.media_id = ? and exists ( select 1 from stories s where s.guid = d.guid and s.media_id = ? )",
        $source_medium->{ media_id }, $target_medium->{ media_id } )->hashes;
    for my $dup_story ( @{ $dup_stories } )
    {
        print "deleting duplicate story '$dup_story->{ title }' ...\n";
        $db->query( "delete from stories where stories_id = ?", $dup_story->{ stories_id } );
        $db->query( "delete from sopa_stories where stories_id = ?", $dup_story->{ stories_id } );
        $db->query( "delete from sopa_links where stories_id = ? or ref_stories_id = ?", 
            $dup_story->{ stories_id }, $dup_story->{ stories_id } );
        $db->query( "delete from story_sentences where stories_id = ?", $dup_story->{ stories_id } );
        $db->query( "delete from story_sentence_words where stories_id = ?", $dup_story->{ stories_id } );
    }

}

# merge the source media into the target medium.  assumes all of the source media are spidered media.
sub merge_into_medium
{
    my ( $db, $target_medium, $source_media, $dedup_stories ) = @_;
    
    for my $source_medium ( @{ $source_media } )
    { 
        next if ( $source_medium->{ media_id } == $target_medium->{ media_id } );
        
        print "$source_medium->{ name } -> $target_medium->{ name }\n";
        
        $db->query( "set enable_seqscan = off" );

        $db->query( "insert into sopa_merged_media ( source_media_id, target_media_id ) values ( ?, ? )",
            $source_medium->{ media_id }, $target_medium->{ media_id } );
            
        $db->query( "update feeds set media_id = ? where media_id = ?", 
            $target_medium->{ media_id }, $source_medium->{ media_id } );
        
        dedup_stories( $db, $target_medium, $source_medium ) if ( $dedup_stories );
                
        $db->query( "update stories set media_id = ? where media_id = ?",
            $target_medium->{ media_id }, $source_medium->{ media_id } );

        $db->query( 
            "update story_sentences set media_id = ? " . 
            "  where stories_id in ( select stories_id from stories where media_id = $source_medium->{ media_id } )",
            $target_medium->{ media_id } );

        $db->query( 
            "update story_sentence_words set media_id = ? " . 
            "  where stories_id in ( select stories_id from stories where media_id = $source_medium->{ media_id } )",
            $target_medium->{ media_id } );
    } 
    
    $db->commit;                           
}

# prompt the user whether to merge the spidered media into one of the original media
sub dedup_media
{
    my ( $db, $domain, $media ) = @_;
    
    print "DOMAIN: $domain\n";
    
    my $original_media = [ grep { !$_->{ is_spidered } } @{ $media } ];
    my $spidered_media = [ grep { $_->{ is_spidered } } @{ $media } ];
    my $media = [ @{ $original_media }, @{ $spidered_media } ];

    print "ORIGINAL MEDIA:\n";
    
    my $i;
    for ( $i = 0; $i < @{ $original_media }; $i++ )
    {
        my $m = $original_media->[ $i ];
        print "$i: $m->{ name } [ $m->{ url } ]\n";
    }

    print "SPIDERED MEDIA:\n";

    for( my $s = 0; $s < @{ $spidered_media }; $s++ )
    {
        my $m = $spidered_media->[ $s ];
        print( ($i + $s ) . ": $m->{ name } [ $m->{ url } ]\n" );
    }
    print "\n";
    
    if ( !@{ $spidered_media } )
    {
        print "no spidered media.  skipping...\n";
        return;
    }
    
    print "Which medium do you want to merge the spidered media into? (enter to skip)\n";
    
    my $answer = <STDIN>;
    chomp( $answer );
    
    return if ( !defined( $answer ) || ( $answer !~ /\d+/ )|| ( !$media->[ $answer ] ) );
    
    my $target_merge_medium = $media->[ $answer ];
    
    eval { merge_into_medium( $db, $target_merge_medium, $spidered_media )  };
    if ( @_ )
    {
        $db = MediaWords::DB::connect_to_db;
        $db->dbh->{ AutoCommit } = 0;
        merge_into_medium( $db, $target_merge_medium, $spidered_media, 1 );  
    }
    
    print "\n";    
}

sub main
{
    my ( $resume ) = @ARGV;
    
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    
    my $db = MediaWords::DB::connect_to_db;
    $db->dbh->{ AutoCommit } = 0;
    
    my $spidered_tag = MediaWords::Util::Tags::lookup_tag( $db, 'spidered:sopa' ) || die( "Unable to find spidered:sopa tag" );
    
    my $media = $db->query( 
        "select m.*, mtm.tags_id is_spidered " . 
        "  from media m left join media_tags_map mtm on ( m.media_id = mtm.media_id and mtm.tags_id = ? ) " .
        "  where m.media_id in ( select s.media_id from stories s, sopa_stories ss where s.stories_id = ss.stories_id ) ",
        $spidered_tag->{ tags_id } )->hashes;
    
    my $media_domain_lookup = {};
    map { push ( @{ $media_domain_lookup->{ get_medium_domain( $_ ) } }, $_ ) } @{ $media };
    
    while ( my ( $domain, $domain_media ) = each( %{ $media_domain_lookup } ) )
    {
        
        next if ( !$domain || @{ $domain_media } < 2 );
        
        next if ( $resume && ( $domain ne $resume ) );

        $resume = undef;

        dedup_media( $db, $domain, $domain_media );
    }   
}

main();