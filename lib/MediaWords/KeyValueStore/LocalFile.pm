package MediaWords::KeyValueStore::LocalFile;

# class for storing / loading objects (raw downloads, CoreNLP annotator results, ...) from / to local files
# currently only works with downloads

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Paths;
use File::Path qw(make_path);
use File::Basename;
use File::Slurp;
use Carp;

# Configuration
has '_conf_data_content_dir' => ( is => 'rw' );

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    # Get arguments
    unless ( $args->{ data_content_dir } )
    {
        die "Please provide 'data_content_dir' argument.\n";
    }
    my $data_content_dir = $args->{ data_content_dir };

    # Store configuration
    $self->_conf_data_content_dir( $data_content_dir );
}

# (static) Returns a directory path for a given path
# (dirname() doesn't cut here because it has "quirks" according to the documentation)
sub _directory_name($)
{
    my $path = shift;

    my ( $filename, $directories, $suffix ) = fileparse( $path );
    return $directories;
}

# Moose method
sub store_content($$$$;$)
{
    my ( $self, $db, $object_id, $content_ref, $skip_encode_and_gzip ) = @_;

    # Encode + gzip
    my $content_to_store;
    if ( $skip_encode_and_gzip )
    {
        $content_to_store = $$content_ref;
    }
    else
    {
        $content_to_store = $self->encode_and_gzip( $content_ref, $object_id, $skip_encode_and_gzip );
    }

    # e.g. "<media_id>/<year>/<month>/<day>/<hour>/<minute>[/<parent download_id>]/<download_id>[.gz]"
    my $relative_path = MediaWords::Util::Paths::get_download_path( $db, $object_id, $skip_encode_and_gzip );
    my $full_path = $self->_conf_data_content_dir . $relative_path;

    # Create missing directories for the path
    make_path( _directory_name( $full_path ) );

    unless ( write_file( $full_path, { binmode => ':raw' }, $content_to_store ) )
    {
        die "Unable to write a file to path '$full_path'.";
    }

    return $relative_path;
}

# Moose method
sub fetch_content($$$$;$)
{
    my ( $self, $db, $object_id, $object_path, $skip_gunzip_and_decode ) = @_;

    unless ( defined $object_path )
    {
        die "Object path for object ID $object_id is undefined.\n";
    }

    my $relative_path = $object_path;
    my $full_path     = $self->_conf_data_content_dir . $relative_path;

    my $content;
    my $decoded_content = '';

    if ( -f $full_path )
    {

        # Read file
        my $gzipped_content = read_file( $full_path, binmode => ':raw' );

        # Gunzip + decode
        $decoded_content = $self->gunzip_and_decode( \$gzipped_content, $object_id );

    }
    else
    {
        $full_path =~ s/\.gz$/.dl/;

        # Read file
        my $content = read_file( $full_path, binmode => ':raw' );

        # Decode
        $decoded_content = Encode::decode( 'utf-8', $content );
    }

    return \$decoded_content;
}

# Moose method
sub remove_content($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    unless ( defined $object_path )
    {
        die "Object path for object ID $object_id is undefined.\n";
    }

    unless ( $self->content_exists( $db, $object_id, $object_path ) )
    {
        die "Content for object ID $object_id doesn't exist so it can't be removed.\n";
    }

    my $relative_path = $object_path;
    my $full_path     = $self->_conf_data_content_dir . $relative_path;

    unless ( -f $full_path )
    {
        $full_path =~ s/\.gz$/.dl/;

        unless ( -f $full_path )
        {
            die "Content for object ID $object_id doesn't exist so it can't be removed.\n";
        }
    }

    unlink( $full_path ) or die "Unable to remove file '$full_path' for object ID $object_id: $@.\n";

    return 1;
}

# Moose method
sub content_exists($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    unless ( defined $object_path )
    {
        die "Object path for object ID $object_id is undefined.\n";
    }

    my $relative_path = $object_path;
    my $full_path     = $self->_conf_data_content_dir . $relative_path;

    if ( -f $full_path )
    {
        return 1;
    }
    else
    {
        $full_path =~ s/\.gz$/.dl/;

        if ( -f $full_path )
        {
            return 1;
        }
        else
        {
            return 0;
        }
    }

}

no Moose;    # gets rid of scaffolding

1;
