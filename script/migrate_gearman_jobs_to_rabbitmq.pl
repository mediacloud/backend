#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Util::JSON;
use Readonly;
use Data::Dumper;

sub main
{
    my $gearman_db = MediaWords::DB::connect_to_db( 'gearman' );

    Readonly my $CHUNK_SIZE => 1000;

    my $loaded_functions = {};

    DEBUG "Migrating Gearman jobs to RabbitMQ...";
    my $jobs_to_process;
    do
    {
        DEBUG "Fetching chunk of up to $CHUNK_SIZE jobs to add to RabbitMQ queue...";

        $gearman_db->begin_work;

        $jobs_to_process = $gearman_db->query(
            <<EOF,
                SELECT unique_key, function_name, data
                FROM queue
                ORDER BY unique_key
                LIMIT ?
EOF
            $CHUNK_SIZE
        )->hashes;

        if ( scalar( @{ $jobs_to_process } ) > 0 )
        {
            DEBUG "Processing " . scalar( @{ $jobs_to_process } ) . " jobs...";

            foreach my $job ( @{ $jobs_to_process } )
            {
                my $unique_key    = $job->{ unique_key };
                my $function_name = $job->{ function_name };
                my $data          = $job->{ data };

                $function_name =~ s/GearmanFunction/Job/;

                unless ( exists $loaded_functions->{ $function_name } )
                {
                    DEBUG( "Loading function '$function_name'..." );

                    eval {
                        ( my $file = $function_name ) =~ s|::|/|g;
                        require $file . '.pm';
                        $function_name->import();
                        1;
                    } or do
                    {
                        my $error = $@;
                        LOGDIE( "Unable to load function '$function_name': $error" );
                    };

                    $loaded_functions->{ $function_name } = 1;
                }

                my $args = MediaWords::Util::JSON::decode_json( $data );

                DEBUG "Adding job '$function_name' with args '$data' to RabbitMQ queue...";
                $function_name->add_to_queue( $args );

                $gearman_db->query(
                    <<EOF,
                    DELETE FROM queue
                    WHERE unique_key = ?
EOF
                    $unique_key
                );
            }

            DEBUG "Done processing " . scalar( @{ $jobs_to_process } ) . " jobs.";
        }
        else
        {
            DEBUG "No more jobs left to process.";
        }

        $gearman_db->commit;

    } until ( scalar( @{ $jobs_to_process } ) == 0 );

    DEBUG "Done migrating Gearman jobs to RabbitMQ.";
}

main();
