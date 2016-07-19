#!/usr/bin/env perl

#
# Add MediaWords::Job::TM::MineTopic job
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CommonLibs;
use MediaWords::TM;
use MediaWords::Job::TM::MineTopic;

sub main
{
    my ( $topic_opt, $import_only, $cache_broken_downloads, $direct_job, $skip_outgoing_foreign_rss_links,
        $skip_post_processing );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    $| = 1;

    Getopt::Long::GetOptions(
        "topic=s"                          => \$topic_opt,
        "import_only!"                     => \$import_only,
        "cache_broken_downloads!"          => \$cache_broken_downloads,
        "direct_job!"                      => \$direct_job,
        "skip_outgoing_foreign_rss_links!" => \$skip_outgoing_foreign_rss_links,
        "skip_post_processing!"            => \$skip_post_processing
    ) || return;

    my $optional_args =
      join( ' ', map { "[ --$_ ]" } qw(direct_job import_only cache_broken_downloads skip_outgoing_foreign_rss_links) );
    die( "usage: $0 --topic < id > $optional_args" ) unless ( $topic_opt );

    my $db = MediaWords::DB::connect_to_db;
    my $topics = MediaWords::TM::require_topics_by_opt( $db, $topic_opt );
    unless ( $topics )
    {
        die "Unable to find topics for option '$topic_opt'";
    }

    for my $topic ( @{ $topics } )
    {
        my $topics_id = $topic->{ topics_id };
        say STDERR "Processing topic $topics_id...";

        if ( $direct_job )
        {
            my $options = {
                import_only                     => $import_only,
                cache_broken_downloads          => $cache_broken_downloads,
                skip_outgoing_foreign_rss_links => $skip_outgoing_foreign_rss_links,
                skip_post_processing            => $skip_post_processing
            };

            MediaWords::TM::Mine::mine_topic( $db, $topic, $options );
        }
        else
        {
            my $args = {
                topics_id                       => $topics_id,
                import_only                     => $import_only,
                cache_broken_downloads          => $cache_broken_downloads,
                skip_outgoing_foreign_rss_links => $skip_outgoing_foreign_rss_links
            };

            my $job_id = MediaWords::Job::TM::MineTopic->add_to_queue( $args );
            say STDERR "Added job with ID: $job_id";
        }

        say STDERR "Done processing topic $topics_id.";
    }
}

main();
