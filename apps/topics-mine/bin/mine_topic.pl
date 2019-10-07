#!/usr/bin/env perl

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;

use MediaWords::DB;
use MediaWords::TM::CLI;
use MediaWords::Job::TM::MineTopic;

sub main
{
    my ( $topic_opt, $import_only, $skip_post_processing, $snapshots_id, $resume_snapshot );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    $| = 1;

    Getopt::Long::GetOptions(
        "topic=s"               => \$topic_opt,
        "import_only!"          => \$import_only,
        "resume_snapshot!"      => \$resume_snapshot,
        "skip_post_processing!" => \$skip_post_processing,
        "snapshots_id=i"        => \$snapshots_id
    ) || return;

    my $args_list = [ qw(import_only skip_post_processing snapshots_id resume_snapshot) ];
    my $optional_args = join( ' ', map { "[ --$_ ]" } @{ $args_list } );
    die( "usage: $0 --topic < id > $optional_args" ) unless ( $topic_opt );

    my $db = MediaWords::DB::connect_to_db();
    my $topics = MediaWords::TM::CLI::require_topics_by_opt( $db, $topic_opt );
    unless ( $topics )
    {
        die "Unable to find topics for option '$topic_opt'";
    }

    for my $topic ( @{ $topics } )
    {
        my $topics_id = $topic->{ topics_id };
        INFO "Processing topic $topics_id...";

        if ( $resume_snapshot )
        {
            ( $snapshots_id ) = $db->query( <<SQL, $topics_id )->flat();
select * from snapshots where topics_id = ? order by snapshots_id desc limit 1
SQL
            die( "no snapshot found for topic $topic->{ topics_id }" ) unless ( $snapshots_id );
        }

        my $args = {
            topics_id            => $topics_id,
            import_only          => $import_only,
            skip_post_processing => $skip_post_processing,
            snapshots_id         => $snapshots_id,
        };

        MediaWords::Job::TM::MineTopic->run( $args );

        INFO "Done processing topic $topics_id.";
    }
}

main();
