package MediaWords::KeyValueStore;

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

# Moose constructor; reads generic connection properties (e.g. host, username,
# password) from Media Cloud configuration itself, but expects to be provided
# with a *specific* destination to write to (e.g. database name, table name,
# S3 bucket and path prefix) as an argument
requires 'BUILD';

# Fetch content; returns reference to content on success; returns empty string
# and dies on error
requires 'fetch_content';

# Store content; returns path to content on success; returns empty string and
# dies on error
requires 'store_content';

# Remove content; returns true if removal was successful, dies on error (e.g.
# when the content doesn't exist)
requires 'remove_content';

# Checks if content exists under a certain key; returns true if it does, false
# if it doesn't, dies on error
requires 'content_exists';

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

no Moose;    # gets rid of scaffolding

1;
