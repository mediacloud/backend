package MediaWords::DBI::Downloads::Store;

# abstract class for storing / loading downloads

use strict;
use warnings;

use Moose::Role;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Encode;
use IO::Compress::Gzip qw(:constants);
use IO::Uncompress::Gunzip;
use MediaWords::Util::Config;

#
# Required methods
#

# Fetch content; returns reference to content on success; returns empty string and dies on error
requires 'fetch_content';

# Store content; returns path to content on success; returns empty string and dies on error
requires 'store_content';

has '_config' => (
    is      => 'ro',
    default => sub { return MediaWords::Util::Config::get_config },
);

# Helper to encode and gzip content
#
# Parameters: content ref; content's identifier, e.g. download ID (optional)
# Returns: gzipped content on success, dies on error
sub encode_and_gzip($$;$)
{
    my ( $self, $content_ref, $content_id ) = @_;

    # Will croak on error
    my $encoded_content = Encode::encode( 'utf-8', $$content_ref );

    my $gzipped_content;

    if ( !( IO::Compress::Gzip::gzip \$encoded_content => \$gzipped_content, -Level => Z_BEST_COMPRESSION, Minimal => 1 ) )
    {
        if ( $content_id )
        {
            die "Unable to gzip content for identifier '$content_id': " . $IO::Compress::Gzip::GzipError . "\n";
        }
        else
        {
            die "Unable to gzip content: $IO::Compress::Gzip::GzipError\n";
        }
    }

    return $gzipped_content;
}

# Helper to gunzip and decode content
#
# Parameters: gzipped content; content's identifier, e.g. download ID (optional)
# Returns: gunzipped content on success, dies on error
sub gunzip_and_decode($$;$)
{
    my ( $self, $gzipped_content_ref, $content_id ) = @_;

    my $content;

    if ( !( IO::Uncompress::Gunzip::gunzip $gzipped_content_ref => \$content ) )
    {
        if ( $content_id )
        {
            die "Unable to gunzip content for identifier '$content_id': " . $IO::Uncompress::Gunzip::GunzipError . "\n";
        }
        else
        {
            die "Unable to gunzip content: $IO::Uncompress::Gunzip::GunzipError\n";
        }
    }

    # Will croak on error
    my $decoded_content = Encode::decode( 'utf-8', $content );

    return $decoded_content;
}

# Get the parent of this download
#
# Parameters: database connection, download hashref
# Returns: parent download hashref or undef
sub _get_parent_download($$$)
{
    my ( $self, $db, $download ) = @_;

    if ( !$download->{ parent } )
    {
        return undef;
    }

    return $db->query( "SELECT * FROM downloads WHERE downloads_id = ?", $download->{ parent } )->hash;
}

# Get the relative path (to be used within the tarball or files) to store the given download
# The path for a download is:
#     <media_id>/<year>/<month>/<day>/<hour>/<minute>[/<parent download_id>]/<download_id>[.gz]
#
# Parameters: database connection, download, (optional) skip gzipping or not
# Returns: string download path
sub get_download_path($$$;$)
{
    my ( $self, $db, $download, $skip_encode_and_gzip ) = @_;

    my $feed = $db->query( "SELECT * FROM feeds WHERE feeds_id = ?", $download->{ feeds_id } )->hash;

    my @date = ( $download->{ download_time } =~ /(\d\d\d\d)-(\d\d)-(\d\d).(\d\d):(\d\d):(\d\d)/ );

    my @path = ( sprintf( "%06d", $feed->{ media_id } ), sprintf( "%06d", $feed->{ feeds_id } ), @date );

    for ( my $p = $self->_get_parent_download( $db, $download ) ; $p ; $p = $self->_get_parent_download( $db, $p ) )
    {
        push( @path, $p->{ downloads_id } );
    }

    push( @path, $download->{ downloads_id } . ( $skip_encode_and_gzip ? '' : '.gz' ) );

    return join( '/', @path );
}

# Return a data directory (with trailing slash)
#
# Returns: data directory (e.g. data/)
sub get_data_dir($)
{
    my ( $self ) = @_;

    my $data_dir = $self->_config->{ mediawords }->{ data_dir };
    $data_dir =~ s!/*$!/!;    # Add a trailing slash
    return $data_dir;
}

# Return a directory to which the Tar / file downloads should be stored (with trailing slash)
#
# Returns: directory (e.g. data/content/) to which downloads will be stored
sub get_data_content_dir($)
{
    my ( $self ) = @_;

    my $data_content_dir = $self->_config->{ mediawords }->{ data_content_dir } || $self->get_data_dir . 'content/';
    $data_content_dir =~ s!/*$!/!;    # Add a trailing slash
    return $data_content_dir;
}

no Moose;                             # gets rid of scaffolding

1;
