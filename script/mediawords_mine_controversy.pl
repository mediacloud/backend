#!/usr/bin/env perl

#
# Add MediaWords::Job::CM::MineControversy job
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
use MediaWords::CM;
use MediaWords::Job::CM::MineControversy;

sub main
{
    my ( $controversy_opt, $import_only, $cache_broken_downloads, $direct_job, $skip_outgoing_foreign_rss_links );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    $| = 1;

    Getopt::Long::GetOptions(
        "controversy=s"                    => \$controversy_opt,
        "import_only!"                     => \$import_only,
        "cache_broken_downloads!"          => \$cache_broken_downloads,
        "direct_job!"                      => \$direct_job,
        "skip_outgoing_foreign_rss_links!" => \$skip_outgoing_foreign_rss_links,
    ) || return;

    my $optional_args =
      join( ' ', map { "[ --$_ ]" } qw(direct_job import_only cache_broken_downloads skip_outgoing_foreign_rss_links) );
    die( "usage: $0 --controversy < id > $optional_args" ) unless ( $controversy_opt );

    my $db = MediaWords::DB::connect_to_db;
    my $controversies = MediaWords::CM::require_controversies_by_opt( $db, $controversy_opt );
    unless ( $controversies )
    {
        die "Unable to find controversies for option '$controversy_opt'";
    }

    for my $controversy ( @{ $controversies } )
    {
        my $controversies_id = $controversy->{ controversies_id };
        say STDERR "Processing controversy $controversies_id...";

        if ( $direct_job )
        {
            my $options = {
                import_only                     => $import_only,
                cache_broken_downloads          => $cache_broken_downloads,
                skip_outgoing_foreign_rss_links => $skip_outgoing_foreign_rss_links
            };

            MediaWords::CM::Mine::mine_controversy( $db, $controversy, $options );
        }
        else
        {
            my $args = {
                controversies_id                => $controversies_id,
                import_only                     => $import_only,
                cache_broken_downloads          => $cache_broken_downloads,
                skip_outgoing_foreign_rss_links => $skip_outgoing_foreign_rss_links
            };

            my $job_id = MediaWords::Job::CM::MineControversy->add_to_queue( $args );
            say STDERR "Added job with ID: $job_id";
        }

        say STDERR "Done processing controversy $controversies_id.";
    }
}

main();
