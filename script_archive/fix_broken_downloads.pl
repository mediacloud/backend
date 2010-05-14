#!/usr/bin/perl

# fix mess from broken path encoding in crawler

use strict;

BEGIN
{
    use FindBin;

    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Crawler::Engine;
use MediaWords::Crawler::Handler;
use IO::Uncompress::Gunzip;

sub get_download_content
{
    my ( $download ) = @_;

    my $fh;
    if ( !( $fh = IO::Uncompress::Gunzip->new( $download->path ) ) )
    {
        die( "error opening file: $!" );
        return;
    }

    my $content;
    while ( my $line = $fh->getline )
    {
        $content .= $line;
    }

    $fh->close;

    return $content;
}

sub main
{

    my $crawler = MediaWords::Crawler::Engine->new();
    my $handler = MediaWords::Crawler::Handler->new( $crawler );

    my $db = $crawler->db;

    my @downloads = $db->resultset( 'Downloads' )->search(
        {
            path => { 'like' => '%----.gz' },
            type  => [ 'feed', 'content' ],
            state => 'success'
        }
    );

    print "Fixing " . scalar( @downloads ) . " downloads ...\n";

    my $path_downloads = {};
    map { push( @{ $path_downloads->{ $_->path } }, $_ ) } @downloads;

    my $i = 0;
    while ( my ( $path, $downloads ) = each( %{ $path_downloads } ) )
    {
        if ( @{ $downloads } == 1 )
        {
            my $download = $downloads->[ 0 ];
            my $old_path = $download->path;
            $handler->_store_download( $download, \"foo" );

            print '[' . $i++ . ']' . " rewriting single download: " . $old_path . " ->\n\t" . $download->path . "\n";
            rename( $old_path, $download->path );

        }
        elsif ( $downloads->[ 0 ]->type eq 'feed' )
        {
            print "[$i] remove " .
              scalar( @{ $downloads } ) . " duplicate feeds: " . $downloads->[ 0 ]->downloads_id . " / " .
              $downloads->[ 0 ]->url . "\n";
            $i += @{ $downloads };
            $db->resultset( 'Downloads' )->search( { downloads_id => [ map { $_->downloads_id } @{ $downloads } ] } )
              ->update(
                {
                    state         => 'error',
                    error_message => 'broken path bug'
                }
              );
        }
        else
        {
            print "[$i] add  " .
              scalar( @{ $downloads } ) . " pending feeds: " . $downloads->[ 0 ]->downloads_id . " / " .
              $downloads->[ 0 ]->url . "\n";
            $i += @{ $downloads };
            $db->resultset( 'Downloads' )->search( { downloads_id => [ map { $_->downloads_id } @{ $downloads } ] } )
              ->update( { state => 'pending' } );
        }
    }
}

main();

