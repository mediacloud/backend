#!/usr/bin/env perl

# manually walk through the given archive, finding and reassigning file info for
# all download files in the archive

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use Archive::Tar::Indexed;
use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

sub main
{
    my ( $archive_file ) = @ARGV;

    die( "usage: $0 <archive file>" ) unless ( $archive_file );

    my $db = MediaWords::DB::connect_to_db;

    my $total_blocks = ( stat( $archive_file ) )[ 7 ] / 512;

    my $files         = [];
    my $current_block = 0;
    while ( my ( $dl_path, $starting_block ) = Archive::Tar::Indexed::get_file_stats( $archive_file, $current_block ) )
    {
        if ( !( $dl_path =~ /\/([0-9]+)\.gz$/ ) )
        {
            warn( "Unable to parse downloads_id from file '$dl_path' at block $current_block" );
            next;
        }

        my $downloads_id = $1;

        push(
            @{ $files },
            {
                path           => $dl_path,
                downloads_id   => $downloads_id,
                starting_block => $starting_block
            }
        );

        print STDERR "[ $downloads_id: $dl_path $starting_block ]\n";

        $current_block = $starting_block + 1;
    }

    for ( my $i = 0 ; $i < @{ $files } ; $i++ )
    {
        my $file = $files->[ $i ];

        my $ending_block = ( $i + 1 > $#{ $files } ) ? $total_blocks : $files->[ $i + 1 ]->{ starting_block };
        my $num_blocks = $ending_block - $file->{ starting_block };

        my $archive_base = $archive_file;
        $archive_base =~ s/.*\/([^\/]+)$/$1/;

        my $tar_id = "tar:$file->{ starting_block }:$num_blocks:$archive_base:$file->{ path }";

        $file->{ path } =~ /\/([0-9]+).gz$/ || die( "unable to parse path: $file->{ path }" );

        my $download = $db->find_by_id( 'downloads', $file->{ downloads_id } );

        if ( !$download )
        {
            warn( "Unable to find download: $file->{ downloads_id }" );
            next;
        }

        if ( $download->{ path } ne $tar_id )
        {
            print STDERR "[ $file->{ downloads_id }: $download->{ path } -> $tar_id ]\n";
            $db->query( "update downloads set path = '$tar_id' where downloads_id = $file->{ downloads_id }" );
        }
    }
}

main();
