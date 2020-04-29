#!/usr/bin/env perl

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;

use MediaWords::DB;
use MediaWords::Job::Broker;
use MediaWords::TM::CLI;
use MediaWords::TM::Snapshot;

sub main
{
    my ( $topic_opt, $note, $snapshots_id );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    $periods = [];

    Getopt::Long::GetOptions(
        "topic=s"      => \$topic_opt,
        "note=s"       => \$note,
        "snapshots_id=i" => \$snapshots_id
    ) || return;

    die( "Usage: $0 --topic < id >" ) unless ( $topic_opt );

    my $db = MediaWords::DB::connect_to_db();
    my $topics = MediaWords::TM::CLI::require_topics_by_opt( $db, $topic_opt );
    unless ( $topics )
    {
        die "Unable to find topics for option '$topic_opt'";
    }

    for my $topic ( @{ $topics } )
    {
        my $topics_id = $topic->{ topics_id };
 
        $snapshots_id = MediaWords::TM::Snapshot::snapshot_topic(
            $db, $topics_id, $snapshots_id, $note,
        );

        INFO "Adding a new word2vec model generation job for snapshot $snapshots_id...";
        MediaWords::Job::Broker->new( 'MediaWords::Job::Word2vec::GenerateSnapshotModel' )->add_to_queue( { snapshots_id => $snapshots_id } );
    }

}

main();

__END__
