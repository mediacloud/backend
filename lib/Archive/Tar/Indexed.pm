package Archive::Tar::Indexed;

# allow fast indexed reading of individual files in a tar file as well as fast appending of new files

use strict;

use File::Path;
use File::Temp ();
use Fcntl ':flock';
use POSIX;

# read the given file from the given tar file at the given starting block with the given number of blocks
# return a ref to the file contents.
sub read_file
{
    my ( $tar_file, $file_name, $starting_block, $num_blocks ) = @_;
    
    my $tar_cmd = "dd if='$tar_file' bs=512 skip=$starting_block count=$num_blocks 2> /dev/null | tar -x -O -f - '$file_name'";
    my $content = `$tar_cmd`;
        
    if ( $content eq '' )
    {
        die( "Unable to retrieve content from tar with '$tar_cmd'" );
    }
    
    return \$content;
}

# append the given file contents to the given tar file under the given path.
# returns the starting block and number of blocks for the file, to be passed
# into read_file.
sub append_file
{
    my ( $tar_file, $file_contents_ref, $file_name ) = @_;
    
    if ( $tar_file =~ /[^a-zA-Z0-9_\-]$/ )
    {
        die( "Only [A-Za-z0-9_\-] allowed with tar file name" );
    }

    my $temp_dir = File::Temp::tempdir || die( "Unable to create temp dir" );
    
    my $file_path = $file_name;
    $file_path =~ s~([^/]+)$~~;

    File::Path::mkpath( "$temp_dir/$file_path" );
        
    if ( !open( FILE, "> $temp_dir/$file_name" ) )
    {
        File::Path::rmtree( $temp_dir );
        die( "Unable to open file '$temp_dir/$file_name': $!" );
    }
    
    print FILE ${ $file_contents_ref };
    
    close( FILE );
    
    if ( !open( TAR_LOCK, ">> $tar_file" ) )
    {
        File::Path::rmtree( $temp_dir );
        die( "Unable to open tar file '$tar_file': $!" );
    }
    
    flock( TAR_LOCK, LOCK_EX );
    
    my $tar_cmd = "tar -r -R -v -C '$temp_dir' -f '$tar_file' '$file_name'";    
    my $tar_output = `$tar_cmd`;    

    flock( TAR_LOCK, LOCK_UN );
    close( TAR_LOCK );

    File::Path::rmtree( $temp_dir );

    if ( !$tar_output )
    {
        die( "Unable to run tar command '$tar_cmd'.  Are you using gnu tar?" );
    }

    if ( !( $tar_output =~ /^block ([0-9]*):/ ) )
    {
        die( "Unable to parse output from tar: '$tar_output'" );
    }

    my $starting_block = $1;
    my $num_blocks = POSIX::ceil( length( ${ $file_contents_ref } ) / 512 ) + 1;
    
    return( $starting_block, $num_blocks );
}

1;