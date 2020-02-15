#!/usr/bin/env perl

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;

use MediaWords::DB;
use MediaWords::TM::CLI;

sub main
{
    my ( $topic_opt, $note, $bot_policy, $periods, $snapshots_id );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    $periods = [];

    Getopt::Long::GetOptions(
        "topic=s"      => \$topic_opt,
        "note=s"       => \$note,
        "bot_policy=s" => \$bot_policy,
        "period=s"     => $periods,
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
        my $args      = {
            topics_id  => $topics_id,
            note       => $note,
            bot_policy => $bot_policy,
            periods    => $periods,
            snapshots_id => $snapshots_id
        };

        MediaWords::Job::TM::SnapshotTopic->run( $args );
    }

}

main();

__END__
