package MediaWords::KeyValueStore::Tar;

# class for storing / loading downloads in tar archives

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Paths;
use Archive::Tar::Indexed;

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

# get the name of the tar file for the download
sub _get_tar_file($$)
{
    my ( $db, $download ) = @_;

    my $date = $download->{ download_time };
    $date =~ s/(\d\d\d\d)-(\d\d)-(\d\d).*/$1$2$3/;
    my $file = "mediacloud-content-$date.tar";

    return $file;
}

# Moose method
sub store_content($$$$;$)
{
    my ( $self, $db, $download, $content_ref, $skip_encode_and_gzip ) = @_;

    my $download_path = MediaWords::Util::Paths::get_download_path( $db, $download, $skip_encode_and_gzip );

    my $tar_file = _get_tar_file( $db, $download );
    my $tar_path = $self->_conf_data_content_dir . $tar_file;

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

    # Store in a Tar archive
    my ( $starting_block, $num_blocks ) =
      Archive::Tar::Indexed::append_file( $tar_path, \$content_to_store, $download_path );

    if ( $num_blocks == 0 )
    {
        my $lengths = join( '/', map { length( $_ ) } ( $$content_ref, $content_to_store ) );
        say STDERR "store_content: num_blocks = 0: $lengths";
    }

    my $tar_id = "tar:$starting_block:$num_blocks:$tar_file:$download_path";

    return $tar_id;
}

# Moose method
sub fetch_content($$$;$)
{
    my ( $self, $db, $download, $skip_gunzip_and_decode ) = @_;

    if ( !( $download->{ path } =~ /tar:(\d+):(\d+):([^:]*):(.*)/ ) )
    {
        warn( "Unable to parse download path: $download->{ path }" );
        return undef;
    }

    my ( $starting_block, $num_blocks, $tar_file, $download_file ) = ( $1, $2, $3, $4 );

    my $tar_path = $self->_conf_data_content_dir . $tar_file;

    # Read from Tar
    my $gzipped_content_ref = Archive::Tar::Indexed::read_file( $tar_path, $download_file, $starting_block, $num_blocks );

    # Gunzip + decode
    my $decoded_content;
    if ( $skip_gunzip_and_decode )
    {
        $decoded_content = $$gzipped_content_ref;
    }
    else
    {
        $decoded_content = $self->gunzip_and_decode( $gzipped_content_ref, $download->{ downloads_id } );
    }

    return \$decoded_content;
}

# Moose method
sub remove_content($$$)
{
    my ( $self, $db, $download ) = @_;

    die "Not sure how to remove Tar content for download " . $download->{ downloads_id } . "\n";

    return 0;
}

# Moose method
sub content_exists($$$)
{
    my ( $self, $db, $download ) = @_;

    die "Not sure how to check whether Tar content exists for download " . $download->{ downloads_id } . "\n";

    return 0;
}

no Moose;    # gets rid of scaffolding

1;
