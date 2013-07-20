#!/usr/bin/env perl
#
# Copy a single download from Tar archive (data/content/*.tar) or local file to GridFS (MongoDB)
#
# Usage:
#
#   ./script/mediawords_copy_single_download_to_gridfs.pl download_id
#
# Define environment variable VERBOSE=1 to see more debugging strings about what's happening.
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;
use MediaWords::DBI::Downloads::Store::DatabaseInline;
use MediaWords::DBI::Downloads::Store::LocalFile;
use MediaWords::DBI::Downloads::Store::Tar;
use MediaWords::DBI::Downloads::Store::GridFS;

# Returns true if verbose output should be used
sub _verbose
{
    return ( exists $ENV{ 'VERBOSE' } and $ENV{ 'VERBOSE' } eq '1' );
}

# Copy content from Tar archives to GridFS
sub copy_tar_to_gridfs($)
{
    my ( $downloads_id ) = @_;

    # Source stores
    my $inline_store    = MediaWords::DBI::Downloads::Store::DatabaseInline->new();
    my $tar_store       = MediaWords::DBI::Downloads::Store::Tar->new();
    my $localfile_store = MediaWords::DBI::Downloads::Store::LocalFile->new();

    # Target store
    my $gridfs_store = MediaWords::DBI::Downloads::Store::GridFS->new();

    my $db = MediaWords::DB::connect_to_db;

    say STDERR "Fetching download with ID $downloads_id...";

    my $download = $db->query(
        <<"EOF",
        SELECT *
        FROM downloads
        WHERE downloads_id = ?
EOF
        $downloads_id
    )->hash;

    unless ( $download )
    {
        die "Download with ID $downloads_id is undef.\n";
    }

    # Choose store
    my $store = undef;
    if ( $download->{ path } =~ /^content:(.*)/ )
    {

        # Inline content
        say STDERR "Will use 'inline' store as a source." if ( _verbose() );
        $store = $inline_store;
    }
    elsif ( $download->{ path } =~ /^gridfs:(.*)/ )
    {

        # GridFS -- don't copy to GridFS
        die "Already in GridFS, skipping download " . $download->{ downloads_id };
    }
    elsif ( $download->{ path } =~ /^tar:/ )
    {

        # Tar
        say STDERR "Will use Tar store as a source." if ( _verbose() );
        $store = $tar_store;
    }
    else
    {

        # Local file
        say STDERR "Will use local file store as a source." if ( _verbose() );
        $store = $localfile_store;
    }

    # Skip the download if it already exists in MongoDB
    if ( $gridfs_store->content_exists( $download ) )
    {

        die "Download " . $download->{ downloads_id } . " already exists in GridFS.";
    }

    say STDERR "Download does not exist in GridFS, will attempt to copy." if ( _verbose() );

    # Skipping gunzipping, decoding, encoding and gzipping again would improve the
    # migration speed, but for the sake of trying MongoDBs stability and performance
    # we go the full way.
    my Readonly $skip_gunzip_and_decode = 0;
    my Readonly $skip_encode_and_gzip   = 0;

    # Fetch from Tar
    my $content_ref;
    eval {
        say STDERR "Fetching download..." if ( _verbose() );
        $content_ref = $store->fetch_content( $download, $skip_gunzip_and_decode );
        say STDERR "Done fetching download." if ( _verbose() );
    };
    if ( $@ or ( !$content_ref ) )
    {
        die "Unable to fetch content for download " . $download->{ downloads_id };
    }

    say STDERR "Download size: " . length( $$content_ref ) if ( _verbose() );
    say STDERR "Will store download to GridFS..." if ( _verbose() );

    # Store to GridFS
    my $gridfs_path = $gridfs_store->store_content( $db, $download, $content_ref, $skip_encode_and_gzip );
    unless ( $gridfs_path )
    {
        die "Unable to store content for download " . $download->{ downloads_id };
    }

    say STDERR "Stored download to GridFS." if ( _verbose() );
}

sub main
{
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    my $downloads_id = $ARGV[ 0 ];
    unless ( $downloads_id )
    {
        die "Usage: $0 downloads_id\n";
    }

    copy_tar_to_gridfs( $downloads_id );
}

main();
