#!/usr/bin/env perl
#
# Verify downloads stored in GridFS and PostgreSQL, verify that they're equal and consistent.
#
# Exits with non-zero status on error.
#
# Usage:
#
#     ./script/mediawords_verify_gridfs_downloads.pl \
#         --mode=from_postgresql_to_gridfs|from_gridfs_to_postgresql \
#         [--start_downloads_id=i] \
#         [--finish_downloads_id=i]
#
# Examples:
#
#     * To test whether all Tar / local file downloads exist in GridFS, run:
#
#         ./script/mediawords_verify_gridfs_downloads.pl \
#             --mode=from_postgresql_to_gridfs
#
#     * To test whether all Tar / local file downloads exist in GridFS up until download ID '10000', run:
#
#         ./script/mediawords_verify_gridfs_downloads.pl \
#             --mode=from_postgresql_to_gridfs \
#             --finish_downloads_id=10000
#
#     * To test whether all Tar / local file downloads exist in GridFS from download ID '10' until download ID '799', run:
#
#         ./script/mediawords_verify_gridfs_downloads.pl \
#             --mode=from_postgresql_to_gridfs \
#             --start_downloads_id=10
#             --finish_downloads_id=700
#
#     * To test whether all downloads currently stored in GridFS exist in their Tar / local file counterparts, run:
#
#         ./script/mediawords_verify_gridfs_downloads.pl \
#             --mode=from_gridfs_to_postgresql
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;
use MediaWords::Util::Paths;
use MediaWords::KeyValueStore::DatabaseInline;
use MediaWords::KeyValueStore::LocalFile;
use MediaWords::KeyValueStore::Tar;
use MediaWords::KeyValueStore::GridFS;
use MongoDB 0.704.1.0;
use Getopt::Long;
use Data::Dumper;

{
    {

        #
        # Helper to iterate over PostgreSQL downloads and fetch their content
        #
        package PostgreSQLAccessor;

        my $_start_downloads_id  = 0;
        my $_finish_downloads_id = 0;
        my $_inline_store        = undef;
        my $_tar_store           = undef;
        my $_gridfs_store        = undef;
        my $_localfile_store     = undef;
        my $_db                  = undef;

        sub new($;$$)
        {
            my ( $class, $start_downloads_id, $finish_downloads_id ) = @_;

            if ( $start_downloads_id )
            {
                $_start_downloads_id = $start_downloads_id - 1;
            }
            if ( $finish_downloads_id )
            {
                $_finish_downloads_id = $finish_downloads_id;
            }

            say STDERR "Initializing PostgreSQL accessor.";

            my $config = MediaWords::Util::Config::get_config;

            # Create stores for reading
            $_inline_store = MediaWords::KeyValueStore::DatabaseInline->new(
                {
                    # no arguments are needed
                }
            );
            $_tar_store =
              MediaWords::KeyValueStore::Tar->new( { data_content_dir => MediaWords::Util::Paths::get_data_content_dir } );
            $_gridfs_store = MediaWords::KeyValueStore::GridFS->new(
                { database_name => $config->{ mongodb_gridfs }->{ downloads }->{ database_name } } );
            $_localfile_store = MediaWords::KeyValueStore::LocalFile->new(
                { data_content_dir => MediaWords::Util::Paths::get_data_content_dir } );

            # Connect to database
            $_db = MediaWords::DB::connect_to_db;

            return bless {}, $class;
        }

        sub get_next_download_id($)
        {
            my ( $self ) = @_;

            my $finish_downloads_id_condition = '';
            if ( $_finish_downloads_id )
            {
                $finish_downloads_id_condition = 'AND downloads_id <= ' . $_finish_downloads_id;
            }

            my $download = $_db->query(
                <<"EOF"
                SELECT *
                FROM downloads
                WHERE downloads_id > $_start_downloads_id
                      $finish_downloads_id_condition
                ORDER BY downloads_id
                LIMIT 1
EOF
            )->hash;
            if ( $download )
            {
                $_start_downloads_id = $download->{ downloads_id };
                return $download->{ downloads_id };
            }
            else
            {
                return 0;
            }

        }

        sub get_content_for_download_id($$)
        {
            my ( $self, $downloads_id ) = @_;

            # Sanity checks
            if ( $_start_downloads_id )
            {
                if ( $downloads_id < $_start_downloads_id )
                {
                    die "Download ID $downloads_id is smaller than the start download ID $_start_downloads_id.\n";
                }
            }
            if ( $_finish_downloads_id )
            {
                if ( $downloads_id > $_finish_downloads_id )
                {
                    die "Download ID $downloads_id is bigger than the finish download ID $_finish_downloads_id.\n";
                }
            }

            my $db_download = $_db->query( 'SELECT * FROM downloads WHERE downloads_id = ?', $downloads_id )->hash;
            unless ( $db_download )
            {

                # Not found
                return ( undef, undef );
            }

            unless (
                (
                       $db_download->{ state } eq 'success'
                    or $db_download->{ state } eq 'error'
                    or $db_download->{ state } eq 'feed_error'
                )
                and $db_download->{ path }
                and (  $db_download->{ file_status } eq 'present'
                    or $db_download->{ file_status } eq 'redownloaded'
                    or $db_download->{ file_status } eq 'tbd'
                    or $db_download->{ file_status } eq 'inline' )
              )
            {
                return ( undef, undef );
            }

            # Choose store
            my $storage_method = undef;
            my $store          = undef;
            if ( $db_download->{ path } =~ /^content:(.*)/ )
            {

                # Inline content
                $storage_method = 'inline';
                $store          = $_inline_store;
            }
            elsif ( $db_download->{ path } =~ /^gridfs:(.*)/ )
            {

                # GridFS
                $storage_method = 'gridfs';
                $store          = $_gridfs_store;
            }
            elsif ( $db_download->{ path } =~ /^tar:/ )
            {

                # Tar
                my $storage_method = 'tar';
                $store = $_tar_store;
            }
            else
            {

                # Local file
                my $storage_method = 'local_file';
                $store = $_localfile_store;
            }

            # Fetch download
            my $content_ref;
            eval {
                $content_ref =
                  $store->fetch_content( $_db, $db_download->{ downloads_id }, $db_download->{ downloads_path } );
            };
            if ( $@ or ( !$content_ref ) )
            {
                return ( $storage_method, undef );
            }

            return ( $storage_method, $$content_ref );
        }
    }

    {

        #
        # Helper to iterate over GridFS downloads and fetch their content
        #
        package GridFSAccessor;

        my $_gridfs_store = undef;
        my $_files_cursor = undef;
        my $_db           = undef;

        sub new($)
        {
            my ( $class ) = @_;

            say STDERR "Initializing GridFS accessor.";

            my $config = MediaWords::Util::Config::get_config;

            # GridFS store
            $_gridfs_store = MediaWords::KeyValueStore::GridFS->new(
                { database_name => $config->{ mongodb_gridfs }->{ downloads }->{ database_name } } );

            # Separate connection to MongoDB to fetch filenames sequentially
            # Get settings
            my $mongo_settings = MediaWords::Util::Config::get_config->{ mongodb_gridfs }->{ mediawords };
            unless ( defined( $mongo_settings ) )
            {
                die "MongoDB connection settings are undefined.\n";
            }

            # Check settings
            my $host          = $mongo_settings->{ host };
            my $port          = $mongo_settings->{ port };
            my $database_name = $mongo_settings->{ database };

            unless ( defined( $host ) and defined( $port ) and defined( $database_name ) )
            {
                die "MongoDB connection settings are invalid.\n";
            }

            # Connect
            my $conn           = MongoDB::Connection->new( host => $host, port => $port );
            my $mongo_db       = $conn->get_database( $database_name );
            my $mongo_db_files = $mongo_db->get_collection( 'fs.files' );
            $_files_cursor = $mongo_db_files->find( {} );    # sorted in "natural order"

            unless ( defined $_files_cursor )
            {
                die "Unable to connect to MongoDB ($host:$port/$database_name).\n";
            }

            $_db = MediaWords::DB::connect_to_db;

            return bless {}, $class;
        }

        sub get_next_download_id($)
        {
            my ( $self ) = @_;

            my $object = $_files_cursor->next;
            return $object->{ filename } + 0;
        }

        sub get_content_for_download_id($$)
        {
            my ( $self, $downloads_id ) = @_;

            my $download = { downloads_id => $downloads_id };

            # Fetch download
            my $content_ref;
            eval {
                $content_ref =
                  $_gridfs_store->fetch_content( $_db, $download->{ downloads_id }, $download->{ downloads_path } );
            };
            if ( $@ or ( !$content_ref ) )
            {
                return ( 'gridfs', undef );
            }

            return ( 'gridfs', $$content_ref );
        }
    }
}

# Available verification modes
my Readonly $FROM_GRIDFS_TO_POSTGRESQL = 1;
my Readonly $FROM_POSTGRESQL_TO_GRIDFS = 2;

sub verify_downloads($$$)
{
    my ( $mode, $start_downloads_id, $finish_downloads_id ) = @_;

    if ( $mode == $FROM_GRIDFS_TO_POSTGRESQL and ( $start_downloads_id or $finish_downloads_id ) )
    {
        die "Download offsets are not supported in GridFS because it stores download IDs as strings (filenames).\n";
    }

    my $gridfs = GridFSAccessor->new();
    my $postgresql = PostgreSQLAccessor->new( $start_downloads_id, $finish_downloads_id );

    my $source_accessor;
    my $destination_accessor;
    if ( $mode == $FROM_GRIDFS_TO_POSTGRESQL )
    {
        say STDERR "Will verify downloads in GridFS against downloads in PostgreSQL.";
        $source_accessor      = $gridfs;
        $destination_accessor = $postgresql;
    }
    else
    {
        say STDERR "Will verify downloads in PostgreSQL against downloads in GridFS.";
        $source_accessor      = $postgresql;
        $destination_accessor = $gridfs;
    }

    my $next_download_id = 0;
    while ( $next_download_id = $source_accessor->get_next_download_id() )
    {
        print STDERR "Verifying download ID " . $next_download_id . "... ";

        # None or both of the contents might be undef
        my ( $source_storage_method, $source_content ) = $source_accessor->get_content_for_download_id( $next_download_id );
        my ( $destination_storage_method, $destination_content ) =
          $destination_accessor->get_content_for_download_id( $next_download_id );

        if ( defined $source_content )
        {
            say STDERR "Expecting content of length " . length( $source_content ) . "...";
        }
        else
        {
            say STDERR "Expecting undefined content...";
        }

        # Either both undefined or equal
        unless (

            # Both "contents" are undefined, or
            ( ( ( !defined $source_content ) and ( !defined $destination_content ) ) )

            # "contents" are defined and equal to each other, or
            or ( defined $source_content and defined $destination_content and $source_content eq $destination_content )

            # inline content is present in source (PostgreSQL) and not in GridFS
            or ( $source_storage_method eq 'inline' and defined $source_content and ( !defined $destination_content ) )

          )
        {

            say STDERR "Warning: Content mismatch for download ID $next_download_id.\n" .
              "Source content: " . ( $source_content || 'undef' ) . "\n" . "Destination content: " .
              ( $destination_content || 'undef' ) . "\n";
        }
    }

    say STDERR "Looks fine to me.";
}

sub main
{
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    my $mode                = '';    # verification mode, either:
                                     # 1) 'from_gridfs_to_postgresql' -- fetch downloads from GridFS, verify them
                                     #    against Tar / file downloads stored in PostgreSQL. Lets one to find out
                                     #    whether all downloads in GridFS are present in the PostgreSQL database.
                                     # 2) 'from_postgresql_to_gridfs' -- fetch Tar / file downloads from PostgreSQL,
                                     #    verify them against downloads in GridFS. Lets one to find out whether all
                                     #    downloads in PostgreSQL are present in the GridFS database.
    my $start_downloads_id  = 0;     # (optional) download's ID to start from; if absent, will start
                                     # from the beginning of all downloads
    my $finish_downloads_id = 0;     # (optional) download's ID to finish at; if absent, will run until
                                     # the end of all downlads

    my Readonly $usage =
      'Usage: ' . $0 . ' --mode=from_postgresql_to_gridfs|from_gridfs_to_postgresql' .
      ' [--start_downloads_id=i]' . ' [--finish_downloads_id=i]';

    GetOptions(
        'mode=s'                => \$mode,
        'start_downloads_id:i'  => \$start_downloads_id,
        'finish_downloads_id:i' => \$finish_downloads_id,
    ) or die "$usage\n";

    if ( $mode eq 'from_gridfs_to_postgresql' )
    {
        $mode = $FROM_GRIDFS_TO_POSTGRESQL;
    }
    elsif ( $mode eq 'from_postgresql_to_gridfs' )
    {
        $mode = $FROM_POSTGRESQL_TO_GRIDFS;
    }
    else
    {
        die "$usage\n";
    }

    say STDERR "starting --  " . localtime();

    if ( $start_downloads_id )
    {
        say STDERR "Will start verifying from download ID $start_downloads_id.";
    }
    else
    {
        say STDERR "Will start verifying from the beginning.";
    }

    if ( $finish_downloads_id )
    {
        say STDERR "Will finish verifying at download ID $finish_downloads_id.";
    }
    else
    {
        say STDERR "Will finish verifying at the end.";
    }

    verify_downloads( $mode, $start_downloads_id, $finish_downloads_id );

    say STDERR "finished --  " . localtime();
}

main();
