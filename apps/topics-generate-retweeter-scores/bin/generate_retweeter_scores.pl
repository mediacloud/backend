#!/usr/bin/env perl

#
# Add MediaWords::Job::GenerateRetweeterScores job
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use File::Slurp;
use Getopt::Long;

use MediaWords::TM::CLI;
use MediaWords::Job::Broker;

sub main
{
    my ( $topic_opt, $name_opt, $users_a_opt, $users_b_opt, $num_partitions_opt, $direct_job, $csv_opt, $match_type_opt );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    $| = 1;

    $users_a_opt = [];
    $users_b_opt = [];

    Getopt::Long::GetOptions(
        "topic=s"          => \$topic_opt,
        "name=s"           => \$name_opt,
        "users_a=s"        => $users_a_opt,
        "users_b=s"        => $users_b_opt,
        "num_partitions=s" => \$num_partitions_opt,
        "direct_job!"      => \$direct_job,
        "csv!"             => \$csv_opt,
        "match_type=s"     => \$match_type_opt
    ) || return;

    unless ( $topic_opt && $name_opt && @{ $users_a_opt } && @{ $users_b_opt } )
    {
        die(
"usage: $0 --topic < id > --name <name > --users_a < retweeted user > --users_b < retweeted user > [--direct_job ]"
        );
    }

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

        my $args = {
            topics_id         => $topics_id,
            name              => $name_opt,
            retweeted_users_a => $users_a_opt,
            retweeted_users_b => $users_b_opt,
            num_partitions    => $num_partitions_opt,
            match_type        => $match_type_opt
        };

        if ( $direct_job )
        {
            my $db = MediaWords::DB::connect_to_db();

            my $topic = $db->require_by_id( 'topics', $topics_id );

            my $score = MediaWords::TM::RetweeterScores::generate_retweeter_scores( $db, $topic, $name_opt, $users_a_opt,
                $users_b_opt, $num_partitions_opt, $match_type_opt );

            if ( $csv_opt )
            {
                my $media_csv = MediaWords::TM::RetweeterScores::generate_media_csv( $db, $score );
                File::Slurp::write_file( 'retweeter_media_' . $topic->{ topics_id } . '.csv', $media_csv );

                my $partition_matrix_csv = MediaWords::TM::RetweeterScores::generate_matrix_csv( $db, $score );
                File::Slurp::write_file( 'retweeter_partition_matrix_' . $topic->{ topics_id } . '.csv',
                    $partition_matrix_csv );
            }

        }
        else
        {
            MediaWords::Job::Broker->new( 'MediaWords::Job::GenerateRetweeterScores' )->add_to_queue( $args );
        }

        INFO "Done processing topic $topics_id.";
    }
}

main();
