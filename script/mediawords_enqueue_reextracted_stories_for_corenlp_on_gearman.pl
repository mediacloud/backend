#!/usr/bin/env perl
#
# Enqueue reextracted stories for CoreNLP annotation.
#
# Usage:
#
#     mediawords_enqueue_reextracted_stories_for_corenlp_on_gearman.pl \
#         [--resume_stories_id_log=corenlp-enqueue-resume-stories_id.log] \
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
use MediaWords::Util::CoreNLP;
use Getopt::Long;
use MediaWords::GearmanFunction::AnnotateWithCoreNLP;
use Scalar::Util qw/looks_like_number/;

# Returns a story's ID to continue enqueueing from
sub _resume_stories_id_from_log($)
{
    my $resume_stories_id_log = shift;

    # Start from the beginning if the resume log doesn't exist
    return 0 unless $resume_stories_id_log;
    return 0 unless -e $resume_stories_id_log;
    return 0 unless -r $resume_stories_id_log;

    open( my $fh, '<', $resume_stories_id_log )
      or die "Could not open resume log '$resume_stories_id_log' for reading: $!\n";
    my $resume_stories_id = <$fh> + 0;
    close $fh;

    if ( $resume_stories_id < 0 )
    {
        $resume_stories_id = 0;
    }

    return $resume_stories_id;
}

# Returns true if verbose output should be used
sub _verbose
{
    return ( exists $ENV{ 'VERBOSE' } and $ENV{ 'VERBOSE' } eq '1' );
}

# Writes the story ID to the skipped stories log
sub _write_skipped_stories_log($$)
{
    my ( $skipped_stories_log, $current_stories_id ) = @_;

    return unless ( $skipped_stories_log );

    open( my $fh, '>>', $skipped_stories_log )
      or die "Could not open skipped stories log '$skipped_stories_log' for writing: $!\n";
    print $fh "$current_stories_id\n";
    close $fh;
}

# Writes the story ID to the resume log
sub _write_stories_id_resume_log($$)
{
    my ( $resume_stories_id_log, $current_stories_id ) = @_;

    # say STDERR "\tWriting $current_stories_id to resume log.";

    return unless ( $resume_stories_id_log );

    open( my $fh, '>', $resume_stories_id_log )
      or die "Could not open resume log '$resume_stories_id_log' for writing: $!\n";
    print $fh $current_stories_id;
    close $fh;

    # say STDERR "\tDone writing $current_stories_id to resume log.";
}

{

    # Semi-global variables so both finish_up() and enqueue_stories_to_corenlp() can use them
    my $global_resume_stories_id_log = undef;
    my $global_resume_stories_id     = 0;
    my $row                          = 0;
    my $rows_analyzed_since_resuming = 0;
    my $stories_found                = 0;
    my $stories_enqueued             = 0;

    # Cleanup tasks after finishing normally or after receiving SIGINT
    sub finish($)
    {
        my $successfully = shift;

        # Write the offset
        _write_stories_id_resume_log( $global_resume_stories_id_log, $global_resume_stories_id );

        say STDERR "Total rows analyzed: $row";
        if ( $global_resume_stories_id )
        {
            say STDERR "Rows analyzed since resuming: $rows_analyzed_since_resuming";
        }
        say STDERR "Stories found: $stories_found (including duplicates)";
        say STDERR "Stories enqueued: $stories_enqueued";
        if ( $global_resume_stories_id_log and ( !$successfully ) )
        {
            say STDERR "Will resume at story ID: $global_resume_stories_id";
        }
    }

    sub finish_after_sigint
    {

        # Assume that the last story is unfinished
        --$global_resume_stories_id;

        say STDERR "^C";

        finish( 0 );
        exit( 1 );
    }

    # Enqueue stories for CoreNLP annotation
    sub enqueue_stories_to_corenlp($$$)
    {
        my ( $resume_stories_id_log, $resume_stories_id, $media_id ) = @_;

        if ( defined $media_id )
        {
            unless ( looks_like_number( $media_id ) )
            {
                die "Media ID '$media_id' is not a number.";
            }
            $media_id = $media_id + 0;
        }

        $global_resume_stories_id_log = $resume_stories_id_log;
        $global_resume_stories_id     = 0;

        my $db = MediaWords::DB::connect_to_db;

        my Readonly $chunk_size = 100;

        $rows_analyzed_since_resuming = 0;
        $stories_found                = 0;
        $stories_enqueued             = 0;

        $row = $resume_stories_id;

        my $media_id_sql = '';
        if ( defined $media_id )
        {
            $media_id_sql = 'media_id = ' . $media_id;
        }
        else
        {
            $media_id_sql = "'t'";
        }

        my $stories = [ 'non-empty array' ];

        while ( scalar( @{ $stories } ) > 0 )    # while there are no more stories
        {
            # Fetch a new chunk of stories
            say STDERR "Fetching chunk of stories..." if ( _verbose() );

            $stories = $db->query(
                <<"EOF"
                SELECT stories_id
                FROM stories
                WHERE stories_id > $resume_stories_id
                  AND db_row_last_updated > collect_date + interval '1 day'
                  AND story_is_annotatable_with_corenlp(stories_id) = 't'
                  AND $media_id_sql
                ORDER BY stories_id
                LIMIT $chunk_size
EOF
            )->hashes;
            say STDERR "Done fetching a chunk of stories." if ( _verbose() );

            say STDERR "Number of results: " . scalar( @{ $stories } ) if ( _verbose() );

            last unless ( scalar( @{ $stories } ) > 0 );    # no more stories

            foreach my $story ( @{ $stories } )
            {
                ++$rows_analyzed_since_resuming;
                ++$row;

                my $stories_id = $story->{ stories_id };

                $global_resume_stories_id = $stories_id;
                $resume_stories_id        = $stories_id;

                # Write the offset
                _write_stories_id_resume_log( $resume_stories_id_log, $stories_id );

                say STDERR "Will attempt to enqueue story " . $stories_id if ( _verbose() );

                ++$stories_found;

                # Duplicate story IDs will be merged into a single Gearman job
                MediaWords::GearmanFunction::AnnotateWithCoreNLP->enqueue_on_gearman( { stories_id => $stories_id } );

                say STDERR "Done enqueuing story " . $stories_id if ( _verbose() );

                ++$stories_enqueued;
            }
        }

        # Show last statistics, etc.
        finish( 1 );

        # Remove the resume log
        if ( $resume_stories_id_log )
        {
            say STDERR "Removing resume log...";
            unlink $resume_stories_id_log;
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

    my $resume_stories_id_log = undef;    # (optional) file into which a resume story ID should be written
    my $media_id              = undef;    # (optional) media ID to which stories should be limited to

    my Readonly $usage =
      'Usage: ' . $0 . ' [--resume_stories_id_log=corenlp-enqueue-resume-stories_id.log]' . ' [--media_id=media_id]';

    GetOptions(
        'resume_stories_id_log:s' => \$resume_stories_id_log,
        'media_id:i'              => \$media_id,
    ) or die "$usage\n";

    say STDERR "starting --  " . localtime();

    my $resume_stories_id = 0;
    if ( $resume_stories_id_log )
    {
        say STDERR "Will use resume log '$resume_stories_id_log'.";

        # Read resume offset (next story's ID that has to be imported)
        $resume_stories_id = _resume_stories_id_from_log( $resume_stories_id_log );
    }
    if ( $resume_stories_id )
    {
        say STDERR "Will resume from story ID " . $resume_stories_id . ".";
    }
    else
    {
        say STDERR "Will start from beginning.";
    }

    if ( defined $media_id )
    {
        say STDERR "Will enqueue only stories with media_id = $media_id.";
    }
    else
    {
        say STDERR "Will enqueue all applicable stories.";
    }

    enqueue_stories_to_corenlp( $resume_stories_id_log, $resume_stories_id, $media_id );

    say STDERR "finished --  " . localtime();
}

main();
