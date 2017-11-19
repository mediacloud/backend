package MediaWords::KeyValueStore;

#
# Abstract class for storing / loading objects (raw downloads, annotator
# results, ...) to / from various storage locations
#

#
# You can use MediaWords::KeyValueStore subpackages
# (MediaWords::KeyValueStore::AmazonS3, MediaWords::KeyValueStore::PostgreSQL, ...)
# to store all kinds of key-value data.
#
# Initializing the store:
#
#     # Initialize PostgreSQL store for storing key-value data to PostgreSQL table
#
#     my $store = MediaWords::KeyValueStore::PostgreSQL->new({
#         # PostgreSQL table name for storing the data in a table's
#         # "raw_data BYTEA NOT NULL" column  (see definition of "raw_downloads"
#         # table in schema/mediawords.sql for a schema example)
#         table => 'pictures_of_my_cats'
#     });
#
# Storing data:
#
#     # In this case, "Vincent Van Furrball" is the key.
#     # The *reference* to the contents of the file "vincent.jpg" is the value.
#
#     $store->store_content( $db, 'Vincent Van Furrball', read_file('vincent.jpg') );
#
# Fetching data:
#
#     # In this case, "Mister Bigglesworth" is the key.
#     # The *reference* to the contents of the file stored in the store is returned.
#
#     my $content = $store->fetch_content( $db, 'Mister Bigglesworth' );
#
# Removing data:
#
#     # Some storage methods might not support removing data
#     eval {
#         $store->remove_content( $db, 'Mister Bigglesworth' );
#     };
#     if ($@) {
#         die "Removing data failed: $@";
#     }
#
# Checking if data exists:
#
#     # Some storage methods might not support checking whether the data exists
#     if ($store->content_exists( $db, 'Mister Bigglesworth' )) {
#         INFO "Yes it does";
#     } else {
#         INFO "No it doesn't";
#     }
#
# For a live example of how the MediaWords::KeyValueStore subpackages are being
# used, see:
#
# * lib/MediaWords/DBI/Downloads.pm -- storing / fetching raw downloads from
#   various kinds of storage methods
# * lib/MediaWords/Util/Annotator/* -- storing / fetching annotator results
#

use strict;
use warnings;

use Moose::Role;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::Util::Compress;

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

# Available compression methods
Readonly our $COMPRESSION_NONE  => 'mc-kvs-compression-none';
Readonly our $COMPRESSION_GZIP  => 'mc-kvs-compression-gzip';
Readonly our $COMPRESSION_BZIP2 => 'mc-kvs-compression-bzip2';

# Helper for validating compression method
sub compression_method_is_valid($$)
{
    my ( $self, $compression_method ) = @_;

    if (   $compression_method eq $MediaWords::KeyValueStore::COMPRESSION_NONE
        or $compression_method eq $MediaWords::KeyValueStore::COMPRESSION_GZIP
        or $compression_method eq $MediaWords::KeyValueStore::COMPRESSION_BZIP2 )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Compress data
sub compress_data_for_method($$$)
{
    my ( $self, $data, $compression_method ) = @_;

    unless ( defined $data )
    {
        LOGCONFESS "Data is undefined.";
    }

    if ( $compression_method eq $COMPRESSION_NONE )
    {
        # no-op
    }
    elsif ( $compression_method eq $COMPRESSION_GZIP )
    {
        $data = MediaWords::Util::Compress::gzip( $data );
    }
    elsif ( $compression_method eq $COMPRESSION_BZIP2 )
    {
        $data = MediaWords::Util::Compress::bzip2( $data );
    }
    else
    {
        LOGCONFESS "Invalid compression method '$compression_method'";
    }

    return $data;
}

# Uncompress data
sub uncompress_data_for_method($$$)
{
    my ( $self, $data, $compression_method ) = @_;

    unless ( defined $data )
    {
        LOGCONFESS "Data is undefined.";
    }

    if ( $compression_method eq $COMPRESSION_NONE )
    {
        # no-op
    }
    elsif ( $compression_method eq $COMPRESSION_GZIP )
    {
        $data = MediaWords::Util::Compress::gunzip( $data );
    }
    elsif ( $compression_method eq $COMPRESSION_BZIP2 )
    {
        $data = MediaWords::Util::Compress::bunzip2( $data );
    }
    else
    {
        LOGCONFESS "Invalid compression method '$compression_method'";
    }

    return $data;
}

no Moose;    # gets rid of scaffolding

1;
