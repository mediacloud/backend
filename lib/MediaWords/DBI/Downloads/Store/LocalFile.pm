package MediaWords::DBI::Downloads::Store::LocalFile;

# class for storing / loading downloads in local files

use strict;
use warnings;

use Moose;
with 'MediaWords::DBI::Downloads::Store';

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use File::Path qw(make_path);
use File::Basename;
use File::Slurp;
use Carp;

# Constructor
sub BUILD
{
    my ( $self, $args ) = @_;

    # say STDERR "New local file download storage.";
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
    my ( $self, $db, $download, $content_ref, $skip_encode_and_gzip ) = @_;

    # Encode + gzip
    my $content_to_store;
    if ( $skip_encode_and_gzip )
    {
        $content_to_store = $$content_ref;
    }
    else
    {
        $content_to_store = $self->encode_and_gzip( $content_ref, $download->{ downloads_id } );
    }

    # e.g. "<media_id>/<year>/<month>/<day>/<hour>/<minute>[/<parent download_id>]/<download_id>[.gz]"
    my $relative_path = $self->get_download_path( $db, $download, $skip_encode_and_gzip );
    my $full_path = $self->get_data_content_dir . $relative_path;

    # Create missing directories for the path
    make_path( _directory_name( $full_path ) );

    unless ( write_file( $full_path, { binmode => ':raw' }, $content_to_store ) )
    {
        die "Unable to write a file to path '$full_path'.";
    }

    return $relative_path;
}

# Moose method
sub fetch_content($$$)
{
    my ( $self, $db, $download ) = @_;

    if ( !$download->{ path } || ( $download->{ state } ne "success" ) )
    {
        return undef;
    }

    my $relative_path = $download->{ path };
    my $full_path     = $self->get_data_content_dir . $relative_path;

    my $content;
    my $decoded_content = '';

    if ( -f $full_path )
    {

        # Read file
        my $gzipped_content = read_file( $full_path, binmode => ':raw' );

        # Gunzip + decode
        $decoded_content = $self->gunzip_and_decode( \$gzipped_content, $download->{ downloads_id } );

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

no Moose;    # gets rid of scaffolding

1;
