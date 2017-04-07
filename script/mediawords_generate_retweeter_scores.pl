#!/usr/bin/env perl

#
# Add MediaWords::Job::GenerateRetweeterScores job
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;

use MediaWords::TM;
use MediaWords::Job::GenerateRetweeterScores;

sub main
{
    my ( $topic_opt, $name_opt, $users_a_opt, $users_b_opt, $num_partitions_opt, $direct_job );

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
        "num_partitions=s" => $num_partitions_opt,
        "direct_job!"      => \$direct_job
    ) || return;

    unless ( $topic_opt && $name_opt && @{ $users_a_opt } && @{ $users_b_opt } )
    {
        die(
"usage: $0 --topic < id > --name <name > --users_a < retweeted user > --users_b < retweeted user > [--direct_job ]"
        );
    }

    my $db = MediaWords::DB::connect_to_db;
    my $topics = MediaWords::TM::require_topics_by_opt( $db, $topic_opt );
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
        };

        if ( $direct_job )
        {
            MediaWords::Job::GenerateRetweeterScores->run_locally( $args );
        }
        else
        {
            my $job_id = MediaWords::Job::GenerateRetweeterScores->add_to_queue( $args );
            INFO "Added job with ID: $job_id";
        }

        INFO "Done processing topic $topics_id.";
    }
}

main();
