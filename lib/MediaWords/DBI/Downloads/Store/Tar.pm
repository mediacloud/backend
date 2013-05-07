package MediaWords::DBI::Downloads::Store::Tar;

# class for storing / loading downloads in tar archives

use strict;
use warnings;

use Moose;
with 'MediaWords::DBI::Downloads::Store';

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use Archive::Tar::Indexed;

my $_data_dir;

# Constructor
sub BUILD
{
    my ( $self, $args ) = @_;

    my $config = MediaWords::Util::Config::get_config;
    $_data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };

    # say STDERR "New Tar download storage.";
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

# get the parent of this download
sub _get_parent($$)
{
    my ( $db, $download ) = @_;

    if ( !$download->{ parent } )
    {
        return undef;
    }

    return $db->query( "select * from downloads where downloads_id = ?", $download->{ parent } )->hash;
}

# get the relative path (to be used within the tarball) to store the given download
# the path for a download is:
# <media_id>/<year>/<month>/<day>/<hour>/<minute>[/<parent download_id>]/<download_id
sub _get_download_path($$)
{
    my ( $db, $download ) = @_;

    my $feed = $db->query( "SELECT * FROM feeds WHERE feeds_id = ?", $download->{ feeds_id } )->hash;

    my @date = ( $download->{ download_time } =~ /(\d\d\d\d)-(\d\d)-(\d\d).(\d\d):(\d\d):(\d\d)/ );

    my @path = ( sprintf( "%06d", $feed->{ media_id } ), sprintf( "%06d", $feed->{ feeds_id } ), @date );

    for ( my $p = _get_parent( $db, $download ) ; $p ; $p = _get_parent( $db, $p ) )
    {
        push( @path, $p->{ downloads_id } );
    }

    push( @path, $download->{ downloads_id } . '.gz' );

    return join( '/', @path );
}

# Moose method
sub store_content($$$$;$)
{
    my ( $self, $db, $download, $content_ref, $skip_encode_and_gzip ) = @_;

    my $download_path = _get_download_path( $db, $download );

    my $tar_file = _get_tar_file( $db, $download );
    my $tar_path = "$_data_dir/content/$tar_file";

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
sub fetch_content($$;$)
{
    my ( $self, $download, $skip_gunzip_and_decode ) = @_;

    if ( !( $download->{ path } =~ /tar:(\d+):(\d+):([^:]*):(.*)/ ) )
    {
        warn( "Unable to parse download path: $download->{ path }" );
        return undef;
    }

    my ( $starting_block, $num_blocks, $tar_file, $download_file ) = ( $1, $2, $3, $4 );

    my $tar_path = "$_data_dir/content/$tar_file";

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

no Moose;    # gets rid of scaffolding

1;
