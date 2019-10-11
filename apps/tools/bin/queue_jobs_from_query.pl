#!/usr/bin/env perl

# queue the results of a postgres query as celery jobs

use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use Getopt::Long;

use MediaWords::DB;
use MediaWords::JobManager::Job;

sub main
{
    my ( $query, $jobs, $priority );

    $jobs = [];

    Getopt::Long::GetOptions(
        "query=s"    => \$query,
        "job=s"      => $jobs,
        "priority=s" => \$priority
    ) || die( "error parsing command line options" );

    die( "usage: $0 --query <postgres query> --job <job name> [ --job <job name> --priority <high|normal|low> ]" )
      unless ( $query && scalar( @{ $jobs } ) );

    die( "illegal job name" ) if ( grep { $_ =~ /[^a-z0-9:]/i } @{ $jobs } );

    $priority ||= 'normal';

    my $db = MediaWords::DB::connect_to_db();

    my $rows = $db->query( $query )->hashes;

    my $num_rows = scalar( @{ $rows } );
    my $i        = 0;
    for my $row ( @{ $rows } )
    {
        $i++;
        my $id_field = ( sort grep { /_id$/ } keys( %{ $row } ) )[ 0 ]
          || ( sort keys( %{ $row } ) )[ 0 ];
        my $id = $row->{ $id_field };

        for my $job ( @{ $jobs } )
        {
            DEBUG( "queueing [$i / $num_rows]: $job $id" );
            MediaWords::JobManager::Job::add_to_queue( "MediaWords::Job::$job", $row, $priority );
            die( "error adding to $job queue: $@\n" . Dumper( $row ) ) if ( $@ );
        }
    }
}

main();
