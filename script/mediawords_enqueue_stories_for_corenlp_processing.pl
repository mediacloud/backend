#!/usr/bin/env perl
#
# Enqueue (extracted) stories for CoreNLP processing (either all of them of
# only a part of the stories based on a certain criteria).
#
# Usage:
#
#     mediawords_enqueue_stories_for_corenlp_processing.pl \
#         [--resume_stories_id_log=stories_id.log] \    # file to keep the last processed "stories_id" in
#         [--overwrite] \                               # overwrite existing annotations (default is not to do that)
#         [--media_id=1] \      # enqueue only stories with a specific "media_id"; may be comma-separated list
#         [--feeds_id=1] \      # enqueue only stories with a specific "feeds_id"; may be comma-separated list
#         [--stories_id=1] \    # enqueue only stories with a specific "stories_id"; may be a comma-separated list
#         [--media_tags_id=1] \ # enqueue only stories with a specific "media_tags_id"; may be a comma-separated list
#         [--stories_tags_id=1] \ # enqueue only stories with a specific "stories_tags_id"; may be a comma-separated list
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
use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;
use MediaWords::Util::CoreNLP;
use Getopt::Long;
use MediaWords::Job::AnnotateWithCoreNLP;
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
    sub enqueue_stories_to_corenlp($$$$)
    {
        my ( $resume_stories_id_log, $resume_stories_id, $limit_by, $overwrite ) = @_;

        for my $limit_by_key ( keys %{ $limit_by } )
        {
            if ( $limit_by->{ $limit_by_key } )
            {
                unless ( ref $limit_by->{ $limit_by_key } eq 'ARRAY' )
                {
                    die "'$limit_by_key' is not arrayref.";
                }
                foreach my $limit_by_value ( @{ $limit_by->{ $limit_by_key } } )
                {
                    unless ( looks_like_number( $limit_by_value ) )
                    {
                        die "'$limit_by_key' value $limit_by_value is not a number.";
                    }

                    $limit_by_value = $limit_by_value + 0;
                }
            }
        }

        $global_resume_stories_id_log = $resume_stories_id_log;
        $global_resume_stories_id     = 0;

        my $db = MediaWords::DB::connect_to_db;

        my Readonly $chunk_size = 100;

        $rows_analyzed_since_resuming = 0;
        $stories_found                = 0;
        $stories_enqueued             = 0;

        $row = $resume_stories_id;

        my @left_joins;
        my @limit_by_conditions;

        my $media_id_sql = '';
        if ( $limit_by->{ media_id } )
        {
            # nothing to LEFT JOIN
            push( @limit_by_conditions, 'stories.media_id IN (' . join( ', ', @{ $limit_by->{ media_id } } ) . ')' );
        }
        if ( $limit_by->{ feeds_id } )
        {
            push( @left_joins, 'LEFT JOIN feeds_stories_map ON stories.stories_id = feeds_stories_map.stories_id' );
            push( @limit_by_conditions,
                'feeds_stories_map.feeds_id IN (' . join( ', ', @{ $limit_by->{ feeds_id } } ) . ')' );
        }
        if ( $limit_by->{ stories_id } )
        {
            # nothing to LEFT JOIN
            push( @limit_by_conditions, 'stories.stories_id IN (' . join( ', ', @{ $limit_by->{ stories_id } } ) . ')' );
        }
        if ( $limit_by->{ media_tags_id } )
        {
            push( @left_joins, 'LEFT JOIN media_tags_map ON stories.media_id = media_tags_map.media_id' );
            push( @limit_by_conditions,
                'media_tags_map.tags_id IN (' . join( ', ', @{ $limit_by->{ media_tags_id } } ) . ')' );
        }
        if ( $limit_by->{ stories_tags_id } )
        {
            push( @left_joins, 'LEFT JOIN stories_tags_map ON stories.stories_id = stories_tags_map.stories_id' );
            push( @limit_by_conditions,
                'stories_tags_map.tags_id IN (' . join( ', ', @{ $limit_by->{ stories_tags_id } } ) . ')' );
        }

        my $limit_by_conditions_str = '';
        if ( scalar @limit_by_conditions )
        {
            $limit_by_conditions_str = ' AND ' . join( ' AND ', @limit_by_conditions );
        }

        my $left_joins_str = '';
        if ( scalar @left_joins )
        {
            $left_joins_str = join( ' ', @left_joins );
        }

        my $stories = [ 'non-empty array' ];

        while ( scalar( @{ $stories } ) > 0 )    # while there are no more stories
        {
            # Fetch a new chunk of stories
            say STDERR "Fetching chunk of stories..." if ( _verbose() );

            $stories = $db->query(
                <<"EOF"
                SELECT DISTINCT stories.stories_id
                FROM stories
                    $left_joins_str
                WHERE stories.stories_id > $resume_stories_id
                  AND story_is_annotatable_with_corenlp(stories.stories_id) = 't'
                  $limit_by_conditions_str
                ORDER BY stories.stories_id
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

                if ( MediaWords::Util::CoreNLP::story_is_annotated( $db, $stories_id ) )
                {
                    if ( $overwrite )
                    {
                        warn "Story $stories_id is already annotated with CoreNLP, will overwrite.";
                    }
                    else
                    {
                        warn "Story $stories_id is already annotated with CoreNLP, skipping.";
                        next;
                    }
                }

                say STDERR "Will attempt to enqueue story " . $stories_id if ( _verbose() );

                ++$stories_found;

                # Duplicate story IDs will be merged into a single job
                MediaWords::Job::AnnotateWithCoreNLP->add_to_queue( { stories_id => $stories_id } );

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
    my $overwrite             = undef;    # (optional) whether to overwrite existing annotations
    my $media_id              = undef;    # (optional) media ID(s) to which stories should be limited to
    my $feeds_id              = undef;    # (optional) feed ID(s) to which stories should be limited to
    my $stories_id            = undef;    # (optional) stories ID(s) to which stories should be limited to
    my $media_tags_id         = undef;    # (optional) media tag ID(s) to which stories should be limited to
    my $stories_tags_id       = undef;    # (optional) story tag ID(s) to which stories should be limited to

    my Readonly $usage = <<"EOF";
        Usage: $0 \
            [--resume_stories_id_log=stories_id.log] \
            [--overwrite] \
            [--media_id=media_id] \
            [--feeds_id=feeds_id] \
            [--stories_id=stories_id] \
            [--media_tags_id=media_tags_id] \
            [--stories_tags_id=stories_tags_id]
EOF

    GetOptions(
        'resume_stories_id_log:s' => \$resume_stories_id_log,
        'overwrite'               => \$overwrite,
        'media_id:s'              => \$media_id,
        'feeds_id:s'              => \$feeds_id,
        'stories_id:s'            => \$stories_id,
        'media_tags_id:s'         => \$media_tags_id,
        'stories_tags_id:s'       => \$stories_tags_id,
    ) or die "$usage\n";

    my $limit_by = {
        media_id        => $media_id        ? [ split( /,/, $media_id ) ]        : undef,
        feeds_id        => $feeds_id        ? [ split( /,/, $feeds_id ) ]        : undef,
        stories_id      => $stories_id      ? [ split( /,/, $stories_id ) ]      : undef,
        media_tags_id   => $media_tags_id   ? [ split( /,/, $media_tags_id ) ]   : undef,
        stories_tags_id => $stories_tags_id ? [ split( /,/, $stories_tags_id ) ] : undef,
    };

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

    if ( $overwrite )
    {
        say STDERR "Will overwrite existing annotations.";
    }
    else
    {
        say STDERR "Will *not* overwrite existing annotations.";
    }

    for my $limit_by_key ( keys %{ $limit_by } )
    {
        if ( $limit_by->{ $limit_by_key } )
        {
            say STDERR "Will enqueue only stories with $limit_by_key IN (" .
              join( ', ', @{ $limit_by->{ $limit_by_key } } ) . ').';
        }
        else
        {
            say STDERR "Will not limit stories by $limit_by_key.";
        }
    }

    enqueue_stories_to_corenlp( $resume_stories_id_log, $resume_stories_id, $limit_by, $overwrite );

    say STDERR "finished --  " . localtime();
}

main();
