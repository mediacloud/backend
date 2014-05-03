package MediaWords::KeyValueStore;

#
# Abstract class for storing / loading objects (raw downloads, CoreNLP
# annotator results, ...) to / from various storage locations
#

#
# You can use MediaWords::KeyValueStore subpackages
# (MediaWords::KeyValueStore::GridFS, MediaWords::KeyValueStore::PostgreSQL, ...)
# to store all kinds of key-value data.
#
# Initializing the store:
#
#     # Initialize GridFS store for storing key-value data to MongoDB GridFS
#
#     my $store = MediaWords::KeyValueStore::GridFS->new({
#         # MongoDB database name for storing the data as GridFS files:
#         database_name => 'pictures_of_my_cats'
#     });
#
#     # Initialize PostgreSQL store for storing key-value data to PostgreSQL table
#
#     my $store = MediaWords::KeyValueStore::PostgreSQL->new({
#         # PostgreSQL table name for storing the data in a table's
#         # "raw_data BYTEA NOT NULL" column  (see definition of "raw_downloads"
#         # table in script/mediawords.sql for a schema example)
#         table_name => 'pictures_of_my_cats'
#     });
#
# Storing data:
#
#     # In this case, "Vincent Van Furrball" is the key.
#     # The *reference* to the contents of the file "vincent.jpg" is the value.
#
#     $store->store_content( $db, 'Vincent Van Furrball', \read_file('vincent.jpg') );
#
#     # Some subpackages of MediaWords::KeyValueStore support additional
#     # parameters for store_content() that define how the object is processed.
#     # For example, MediaWords::KeyValueStore::GridFS::store_content() supports
#     # the following parameters:
#     # * $skip_encode_and_compress -- skip encoding with Encode and compressing
#     #   data with Gzip
#     # * $use_bzip2_instead_of_gzip -- use Bzip2 compression instead of Gzip
#     # Make sure to read the declaration of the store_content() for the specific
#     # subpackage subroutine before using it.
#
#     my $skip_encode_and_compress = undef;   # default value
#     my $use_bzip2_instead_of_gzip = 1;
#     $gridfs_store->store_content(
#         $db,
#         'Cuddles McCracken',
#         \read_file('cuddles.jpg'),
#         $skip_encode_and_compress,
#         $use_bzip2_instead_of_gzip
#     );
#
# Fetching data:
#
#     # In this case, "Mister Bigglesworth" is the key.
#     # The *reference* to the contents of the file stored in the store is returned.
#
#     my $content_ref = $store->fetch_content( $db, 'Mister Bigglesworth' );
#
#     # Some subpackages of MediaWords::KeyValueStore support additional
#     # parameters for fetch_content() that define how the object is processed.
#     # For example, MediaWords::KeyValueStore::GridFS::fetch_content() supports
#     # the following parameters:
#     # * $object_path -- object path (MongoDB OID); not used
#     # * $skip_uncompress_and_decode -- skip uncompressing with Gunzip and
#     #   decoding with Encode
#     # * $use_bzip2_instead_of_gzip -- use Bzip2 uncompression instead of Gzip
#     # Make sure to read the declaration of the fetch_content() for the specific
#     # subpackage subroutine before using it.
#
#     my $object_path = undef;    # default value
#     my $skip_uncompress_and_decode = undef; # default value
#     my $use_bzip2_instead_of_gzip = 1;
#     my $content_ref = $gridfs_store->fetch_content(
#         $db,
#         'Mister Bigglesworth',
#         $object_path,
#         $skip_uncompress_and_decode,
#         $use_bzip2_instead_of_gzip
#     );
#
# Removing data:
#
#     # Some storage methods don't support removing data, e.g. Tar
#     eval {
#         $store->remove_content( $db, 'Mister Bigglesworth' );
#     };
#     if ($@) {
#         die "Removing data failed: $@";
#     }
#
# Checking if data exists:
#
#     # Some storage methods don't support checking if the data exists, e.g. Tar
#     if ($store->content_exists( $db, 'Mister Bigglesworth' )) {
#         say "Yes it does";
#     } else {
#         say "No it doesn't";
#     }
#
# For a live example of how the MediaWords::KeyValueStore subpackages are being
# used, see:
#
# * lib/MediaWords/DBI/Downloads.pm -- storing / fetching raw downloads from
#   various kinds of storage methods
# * lib/MediaWords/Util/CoreNLP.pm -- storing / fetching CoreNLP annotator
#   results from / to MongoDB GridFS
#

use strict;
use warnings;

use Moose::Role;

use Modern::Perl "2013";
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

# Helper to encode and compress content
#
# Parameters:
# * content ref
# * content's identifier, e.g. download ID (optional)
# * true if the subroutine should use Bzip2 instead of Gzip (optional)
# Returns: compressed content on success, dies on error
sub encode_and_compress($$;$$)
{
    my ( $self, $content_ref, $content_id, $use_bzip2_instead_of_gzip ) = @_;

    my $encoded_and_compressed_content;
    eval {
        if ( $use_bzip2_instead_of_gzip )
        {
            $encoded_and_compressed_content = MediaWords::Util::Compress::encode_and_bzip2( $$content_ref );
        }
        else
        {
            $encoded_and_compressed_content = MediaWords::Util::Compress::encode_and_gzip( $$content_ref );
        }

    };
    if ( $@ or ( !defined $encoded_and_compressed_content ) )
    {
        if ( $content_id )
        {
            die "Unable to compress content for identifier '$content_id': $@";
        }
        else
        {
            die "Unable to compress content: $@";
        }

    }

    return $encoded_and_compressed_content;
}

# Helper to uncompress and decode content
#
# Parameters:
# * compressed content;
# * content's identifier, e.g. download ID (optional)
# * true if the subroutine should use Bunzip2 instead of Gunzip (optional)
# Returns: uncompressed content on success, dies on error
sub uncompress_and_decode($$;$$)
{
    my ( $self, $content_ref, $content_id, $use_bunzip2_instead_of_gunzip ) = @_;

    my $uncompressed_and_decoded_content;
    eval {
        if ( $use_bunzip2_instead_of_gunzip )
        {
            $uncompressed_and_decoded_content = MediaWords::Util::Compress::bunzip2_and_decode( $$content_ref );
        }
        else
        {
            $uncompressed_and_decoded_content = MediaWords::Util::Compress::gunzip_and_decode( $$content_ref );
        }
    };
    if ( $@ or ( !defined $uncompressed_and_decoded_content ) )
    {
        if ( $content_id )
        {
            die "Unable to uncompress content for identifier '$content_id': $@";
        }
        else
        {
            die "Unable to uncompress content: $@";
        }
    }

    return $uncompressed_and_decoded_content;
}

no Moose;    # gets rid of scaffolding

1;
