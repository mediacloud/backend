#!/usr/bin/env perl

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Media::Rescrape;
use MediaWords::Job::StatefulBroker;


sub run_job($)
{
    my $args = shift;

    my $db = MediaWords::DB::connect_to_db();

    my $media_id = $args->{ media_id };
    unless ( defined $media_id )
    {
        die "'media_id' is undefined.";
    }

    if ( $media_id == 361045 )
    {
        die "Job with media_id = 361045 manages to segfault me";
    }

    MediaWords::DBI::Media::Rescrape::rescrape_media( $db, $media_id );
}

sub main()
{
    my $app = MediaWords::Job::StatefulBroker->new( 'MediaWords::Job::RescrapeMedia' );

    my $lock = undef;
    my $extra_table = undef;
    my $state = MediaWords::Job::State->new( $extra_table );
    $app->start_worker( \&run_job, $lock, $state );
}

main();
