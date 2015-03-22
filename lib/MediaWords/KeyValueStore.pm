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
#     # * $use_bzip2_instead_of_gzip -- use Bzip2 compression instead of Gzip
#     # Make sure to read the declaration of the store_content() for the specific
#     # subpackage subroutine before using it.
#
#     my $use_bzip2_instead_of_gzip = 1;
#     $gridfs_store->store_content(
#         $db,
#         'Cuddles McCracken',
#         \read_file('cuddles.jpg'),
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
#     # * $use_bzip2_instead_of_gzip -- use Bzip2 uncompression instead of Gzip
#     # Make sure to read the declaration of the fetch_content() for the specific
#     # subpackage subroutine before using it.
#
#     my $object_path = undef;    # default value
#     my $use_bzip2_instead_of_gzip = 1;
#     my $content_ref = $gridfs_store->fetch_content(
#         $db,
#         'Mister Bigglesworth',
#         $object_path,
#         $use_bzip2_instead_of_gzip
#     );
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

no Moose;    # gets rid of scaffolding

1;
