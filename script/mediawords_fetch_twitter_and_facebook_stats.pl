#!/usr/bin/env perl

#
# fetch twitter and facebook statistics for all stories in a controversy
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Getopt::Long;

use MediaWords::DB;
use MediaWords::CM;
use MediaWords::Util::Facebook;
use MediaWords::GearmanFunction;
use MediaWords::GearmanFunction::Twitter::FetchStoryStats;

sub main
{
    my ( $controversy_opt, $direct_job );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    Readonly my $usage => <<EOF;
Usage: $0 --controversy < id > [--direct_job]
EOF

    Getopt::Long::GetOptions(
        "controversy=s" => \$controversy_opt,
        "direct_job!"   => \$direct_job
    ) or die $usage;
    die $usage unless ( $controversy_opt );

    unless ( $direct_job )
    {
        unless ( MediaWords::GearmanFunction::gearman_is_enabled() )
        {
            die "Gearman is disabled.";
        }
    }

    my $db = MediaWords::DB::connect_to_db;
    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );
    unless ( $controversies )
    {
        die "Unable to find controversies for option '$controversy_opt'";
    }

    for my $controversy ( @{ $controversies } )
    {
        my $controversies_id = $controversy->{ controversies_id };

        my $stories = $db->query( <<END, $controversies_id )->hashes;
            SELECT stories_id
            FROM controversy_stories
            WHERE controversies_id = ?
END

        unless ( scalar @{ $stories } )
        {
            say STDERR "No stories found for controversy '$controversy->{ name }' ('$controversy_opt')";
        }

        for my $story ( @{ $stories } )
        {
            my $stories_id = $story->{ stories_id };
            my $args = { stories_id => $stories_id };

            if ( $direct_job )
            {
                say STDERR "Running local job for story $stories_id...";
                MediaWords::GearmanFunction::Twitter::FetchStoryStats->run_locally( $args );
            }
            else
            {
                say STDERR "Enqueueing Gearman job for story $stories_id...";
                MediaWords::GearmanFunction::Twitter::FetchStoryStats->enqueue_on_gearman( $args );
            }

            # if ( !$ss || $ss->{ facebook_share_count_error} || !defined( $ss->{ facebook_share_count } ) )
            # {
            #     my $count = MediaWords::Util::Facebook::get_and_store_share_count( $db, $story );
            #     say STDERR "facebook_share_count: $count";
            # }
        }
    }
}

main();
