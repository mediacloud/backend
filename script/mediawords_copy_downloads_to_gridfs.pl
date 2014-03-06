#!/usr/bin/env perl
#
# Copy downloads from Tar archives (data/content/*.tar) and local files to GridFS (MongoDB)
#
# Usage:
#
#   ./script/mediawords_sync_downloads_from_tar_to_gridfs.pl \
#       --resume_downloads_id_log=gridfs-resume-downloads_id.log
#
# (then, to resume from where the script stopped, run the very same command again)
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
use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;
use MediaWords::Util::Paths;
use MediaWords::KeyValueStore::LocalFile;
use MediaWords::KeyValueStore::Tar;
use MediaWords::KeyValueStore::GridFS;
use Getopt::Long;

{

    #
    # Two ways to show migration progress
    # Uncomment your favourite one
    #

    # Show migration progress via progressbar
    # use Term::ProgressBar 2.00;
    # my $progress;
    # sub _show_progress($$$)
    # {
    #     my ($current, $target, $chunk_size) = @_;

    #     unless ($progress)
    #     {
    #         $progress = Term::ProgressBar->new({
    #             name  => 'Tar -> GridFS',
    #             count => $target,
    #             ETA   => 'linear',
    #         });
    #     }

    #     $progress->update($current-1);
    # }

    # Show migration progress via text
    sub _show_progress($$$)
    {
        my ( $current, $target, $chunk_size ) = @_;

        say STDERR "Analyzing download ID $current / ~$target...";
    }

}

# Returns a download's ID to continue copying from
sub _resume_downloads_id_from_log($)
{
    my $resume_downloads_id_log = shift;

    # Start from the beginning if the resume log doesn't exist
    return 0 unless $resume_downloads_id_log;
    return 0 unless -e $resume_downloads_id_log;
    return 0 unless -r $resume_downloads_id_log;

    open( my $fh, '<', $resume_downloads_id_log )
      or die "Could not open resume log '$resume_downloads_id_log' for reading: $!\n";
    my $resume_downloads_id = <$fh> + 0;
    close $fh;

    if ( $resume_downloads_id < 0 )
    {
        $resume_downloads_id = 0;
    }

    return $resume_downloads_id;
}

# Returns true if verbose output should be used
sub _verbose
{
    return ( exists $ENV{ 'VERBOSE' } and $ENV{ 'VERBOSE' } eq '1' );
}

# Writes the download ID to the skipped downloads log
sub _write_skipped_downloads_log($$)
{
    my ( $skipped_downloads_log, $current_downloads_id ) = @_;

    return unless ( $skipped_downloads_log );

    open( my $fh, '>>', $skipped_downloads_log )
      or die "Could not open skipped downloads log '$skipped_downloads_log' for writing: $!\n";
    print $fh "$current_downloads_id\n";
    close $fh;
}

# Writes the download ID to the resume log
sub _write_downloads_id_resume_log($$)
{
    my ( $resume_downloads_id_log, $current_downloads_id ) = @_;

    # say STDERR "\tWriting $current_downloads_id to resume log.";

    return unless ( $resume_downloads_id_log );

    open( my $fh, '>', $resume_downloads_id_log )
      or die "Could not open resume log '$resume_downloads_id_log' for writing: $!\n";
    print $fh $current_downloads_id;
    close $fh;

    # say STDERR "\tDone writing $current_downloads_id to resume log.";
}

{

    # Semi-global variables so both finish_up() and copy_tar_to_gridfs() can use them
    my $global_resume_downloads_id_log = undef;
    my $global_resume_downloads_id     = 0;
    my $db                             = undef;
    my $row                            = 0;
    my $rows_analyzed_since_resuming   = 0;
    my $downloads_found                = 0;
    my $downloads_copied               = 0;

    # Cleanup tasks after finishing normally or after receiving SIGINT
    sub finish($)
    {
        my $successfully = shift;

        # Write the offset
        _write_downloads_id_resume_log( $global_resume_downloads_id_log, $global_resume_downloads_id );

        say STDERR "Total rows analyzed: $row";
        if ( $global_resume_downloads_id )
        {
            say STDERR "Rows analyzed since resuming: $rows_analyzed_since_resuming";
        }
        say STDERR "Downloads found: $downloads_found (including duplicates)";
        say STDERR "Downloads copied: $downloads_copied";
        if ( $global_resume_downloads_id_log and ( !$successfully ) )
        {
            say STDERR "Will resume at download ID: $global_resume_downloads_id";
        }
    }

    sub finish_after_sigint
    {

        # Assume that the last download is unfinished
        --$global_resume_downloads_id;

        say STDERR "^C";

        finish( 0 );
        exit( 1 );
    }

    # Copy content from Tar archives to GridFS
    sub copy_tar_to_gridfs($$$)
    {
        my ( $resume_downloads_id_log, $resume_downloads_id, $skipped_downloads_log ) = @_;

        $global_resume_downloads_id_log = $resume_downloads_id_log;
        $global_resume_downloads_id     = 0;

        # Source stores
        my $tar_store =
          MediaWords::KeyValueStore::Tar->new( { data_content_dir => MediaWords::Util::Paths::get_data_content_dir } );
        my $localfile_store =
          MediaWords::KeyValueStore::LocalFile->new( { data_content_dir => MediaWords::Util::Paths::get_data_content_dir } );

        # Target store
        my $config       = MediaWords::Util::Config::get_config;
        my $gridfs_store = MediaWords::KeyValueStore::GridFS->new(
            { database_name => $config->{ mongodb_gridfs }->{ downloads }->{ database_name } } );

        $db = MediaWords::DB::connect_to_db;

        # Average number of rows for the progress bar
        say STDERR "Fetching average number of downloads..." if ( _verbose() );
        my $num_rows = $db->query(
            <<"EOF"
            SELECT downloads_id AS avg_row_count
            FROM downloads
            ORDER BY downloads_id DESC
            LIMIT 1
EOF
        )->hash;
        say STDERR "Done fetching average number of downloads." if ( _verbose() );

        $num_rows = $num_rows->{ avg_row_count };
        say STDERR "Will run through ~$num_rows rows" . ( $resume_downloads_id ? ', minus offset.' : '.' );

        my Readonly $chunk_size = 1000;

        $rows_analyzed_since_resuming = 0;
        $downloads_found              = 0;
        $downloads_copied             = 0;

        $row = $resume_downloads_id;

        my $downloads = [ 'non-empty array' ];

        while ( scalar( @{ $downloads } ) > 0 )    # while there are no more downloads
        {

            # Fetch a new chunk of downloads
            say STDERR "Fetching chunk of downloads..." if ( _verbose() );

            # It would make sense to have "WHERE path LIKE 'tar:%' AND ..." here, but that way
            # the progress meter is very uneven
            $downloads = $db->query(
                <<"EOF"
                SELECT *
                FROM downloads
                WHERE downloads_id > $resume_downloads_id
                ORDER BY downloads_id
                LIMIT $chunk_size
EOF
            )->hashes;
            say STDERR "Done fetching a chunk of downloads." if ( _verbose() );

            say STDERR "Number of results: " . scalar( @{ $downloads } ) if ( _verbose() );

            last unless ( scalar( @{ $downloads } ) > 0 );    # no more downloads

            _show_progress( $downloads->[ 0 ]->{ downloads_id }, $num_rows, $chunk_size );

            foreach my $download ( @{ $downloads } )
            {
                ++$rows_analyzed_since_resuming;
                ++$row;

                $global_resume_downloads_id = $download->{ downloads_id };
                $resume_downloads_id        = $download->{ downloads_id };

                # Write the offset
                _write_downloads_id_resume_log( $resume_downloads_id_log, $download->{ downloads_id } );

                if (
                        $download->{ state } eq 'success'
                    and $download->{ path }
                    and (  $download->{ file_status } eq 'present'
                        or $download->{ file_status } eq 'redownloaded'
                        or $download->{ file_status } eq 'tbd' )
                  )
                {
                    say STDERR "Download path: " . $download->{ path } . "" if ( _verbose() );

                    # Choose store
                    my $store = undef;
                    if ( $download->{ path } =~ /^content:(.*)/ )
                    {

                        # Inline content -- don't copy to GridFS
                        say STDERR "Inline content, skipping..." if ( _verbose() );
                        next;
                    }
                    elsif ( $download->{ path } =~ /^gridfs:(.*)/ )
                    {

                        # GridFS -- don't copy to GridFS
                        say STDERR "Already in GridFS, skipping download " . $download->{ downloads_id } . "...";
                        next;
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

                    say STDERR "Will attempt to write download " . $download->{ downloads_id } if ( _verbose() );

                    ++$downloads_found;

                    # Skip the download if it already exists in MongoDB
                    if ( $gridfs_store->content_exists( $db, $download ) )
                    {

                        say STDERR "Download " . $download->{ downloads_id } . " already exists, skipping.";
                        next;
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
                        $content_ref = $store->fetch_content( $db, $download, $skip_gunzip_and_decode );
                        say STDERR "Done fetching download." if ( _verbose() );
                    };
                    if ( $@ or ( !$content_ref ) )
                    {
                        say STDERR "Unable to fetch content for download " . $download->{ downloads_id } . ", skipping...";
                        _write_skipped_downloads_log( $skipped_downloads_log, $download->{ downloads_id } );
                        next;
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

                    ++$downloads_copied;

                    say STDERR "Done writing download " . $download->{ downloads_id } if ( _verbose() );

                }

            }
        }

        _show_progress( $global_resume_downloads_id, $num_rows, $chunk_size );

        # Show last statistics, etc.
        finish( 1 );

        # Remove the resume log
        if ( $resume_downloads_id_log )
        {
            say STDERR "Removing resume log...";
            unlink $resume_downloads_id_log;
        }
    }

    # Catch SIGINTs because sometimes after aborting the script might not be able to write
    # the resume log or finish some other important task
    $SIG{ 'INT' } = 'finish_after_sigint';

}

sub main
{
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    my $resume_downloads_id_log = undef;    # (optional) file into which a resume download ID should be written
    my $skipped_downloads_log   = undef;    # (optional) file into which skipped download IDs should be written

    my Readonly $usage =
      'Usage: ' . $0 .
      ' [--resume_downloads_id_log=gridfs-resume-downloads_id.log]' . ' [--skipped_downloads_log=skipped-downloads.log]';

    GetOptions(
        'resume_downloads_id_log:s' => \$resume_downloads_id_log,
        'skipped_downloads_log:s'   => \$skipped_downloads_log,
    ) or die "$usage\n";

    say STDERR "starting --  " . localtime();

    my $resume_downloads_id = 0;
    if ( $resume_downloads_id_log )
    {
        say STDERR "Will use resume log '$resume_downloads_id_log'.";

        # Read resume offset (next download's ID that has to be imported)
        $resume_downloads_id = _resume_downloads_id_from_log( $resume_downloads_id_log );
    }
    if ( $resume_downloads_id )
    {
        say STDERR "Will resume from download ID " . $resume_downloads_id . ".";
    }
    else
    {
        say STDERR "Will start from beginning.";
    }
    if ( $skipped_downloads_log )
    {
        say STDERR "Will log skipped downloads to '$skipped_downloads_log'.";
    }
    else
    {
        say STDERR "Will not log skipped downloads.";
    }

    copy_tar_to_gridfs( $resume_downloads_id_log, $resume_downloads_id, $skipped_downloads_log );

    say STDERR "finished --  " . localtime();
}

main();
