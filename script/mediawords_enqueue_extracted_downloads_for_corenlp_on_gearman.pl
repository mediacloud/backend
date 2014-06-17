#!/usr/bin/env perl
#
# Enqueue extracted downloads for CoreNLP annotation.
#
# It is safe to run this as many times as you want because the extraction job
# on Gearman is unique so download extractions won't be duplicated.
#
# Usage:
#
#     mediawords_enqueue_extracted_downloads_for_corenlp_on_gearman.pl \
#         [--resume_downloads_id_log=corenlp-enqueue-resume-downloads_id.log] \
#         [--media_id=1]
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
use Getopt::Long;
use MediaWords::GearmanFunction::AnnotateWithCoreNLP;
use Scalar::Util qw/looks_like_number/;

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
    #             name  => 'CoreNLP',
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

        say STDERR "At download ID $current / ~$target...";
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

    # Semi-global variables so both finish_up() and enqueue_downloads_to_corenlp() can use them
    my $global_resume_downloads_id_log = undef;
    my $global_resume_downloads_id     = 0;
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

    # Enqueue downloads for CoreNLP annotation
    sub enqueue_downloads_to_corenlp($$$)
    {
        my ( $resume_downloads_id_log, $resume_downloads_id, $media_id ) = @_;

        if ( defined $media_id )
        {
            unless ( looks_like_number( $media_id ) )
            {
                die "Media ID '$media_id' is not a number.";
            }
            $media_id = $media_id + 0;
        }

        $global_resume_downloads_id_log = $resume_downloads_id_log;
        $global_resume_downloads_id     = 0;

        my $db = MediaWords::DB::connect_to_db;

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

        my Readonly $chunk_size = 100;

        $rows_analyzed_since_resuming = 0;
        $downloads_found              = 0;
        $downloads_copied             = 0;

        $row = $resume_downloads_id;

        my $media_id_sql = '';
        if ( defined $media_id )
        {
            $media_id_sql = 'stories.media_id = ' . $media_id;
        }
        else
        {
            $media_id_sql = "'t'";
        }

        my $downloads = [ 'non-empty array' ];

        while ( scalar( @{ $downloads } ) > 0 )    # while there are no more downloads
        {

            # Fetch a new chunk of downloads
            say STDERR "Fetching chunk of downloads..." if ( _verbose() );

            # It would make sense to have "WHERE path LIKE 'tar:%' AND ..." here, but that way
            # the progress meter is very uneven
            $downloads = $db->query(
                <<"EOF"
                SELECT downloads.*
                FROM downloads
                    -- Needed for limiting a list of downloads to a certain media_id
                    INNER JOIN stories ON downloads.stories_id = stories.stories_id
                WHERE downloads_id > $resume_downloads_id
                  AND downloads.extracted = 't'
                  AND downloads.type = 'content'
                  AND downloads.state = 'success'
                  AND story_is_annotatable_with_corenlp(downloads.stories_id) = 't'
                  AND $media_id_sql
                ORDER BY downloads.downloads_id
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

                say STDERR "Will attempt to enqueue download " . $download->{ downloads_id } if ( _verbose() );

                ++$downloads_found;

                MediaWords::GearmanFunction::AnnotateWithCoreNLP->enqueue_on_gearman( $download );

                say STDERR "Done enqueueing download " . $download->{ downloads_id } if ( _verbose() );

                ++$downloads_copied;
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
    my $media_id                = undef;    # (optional) media ID to which downloads should be limited to

    my Readonly $usage =
      'Usage: ' . $0 . ' [--resume_downloads_id_log=corenlp-enqueue-resume-downloads_id.log]' . ' [--media_id=media_id]';

    GetOptions(
        'resume_downloads_id_log:s' => \$resume_downloads_id_log,
        'media_id:i'                => \$media_id,
    ) or die "$usage\n";

    say STDERR "starting --  " . localtime();

    my $resume_downloads_id = 0;
    if ( $resume_downloads_id_log )
    {
        say STDERR "Will use resume log '$resume_downloads_id_log'.";

        # Read resume offset (next download's ID that has to be imported)
        $resume_downloads_id = _resume_downloads_id_from_log( $resume_downloads_id_log );
    }
    if ( defined $resume_downloads_id )
    {
        say STDERR "Will resume from download ID " . $resume_downloads_id . ".";
    }
    else
    {
        say STDERR "Will start from beginning.";
    }
    if ( defined $media_id )
    {
        say STDERR "Will enqueue only downloads with media.media_id = $media_id.";
    }
    else
    {
        say STDERR "Will enqueue all applicable downloads.";
    }

    enqueue_downloads_to_corenlp( $resume_downloads_id_log, $resume_downloads_id, $media_id );

    say STDERR "finished --  " . localtime();
}

main();
