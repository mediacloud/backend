#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::KeyValueStore::PostgreSQL;
use MediaWords::KeyValueStore::AmazonS3;

use Readonly;
use Parallel::Fork::BossWorkerAsync;

my %postgresql_stores;
my %s3_stores;

sub _get_postgresql_store_for_current_pid()
{
    my $pid = $$;

    unless ( $postgresql_stores{ $pid } )
    {
        $postgresql_stores{ $pid } = MediaWords::KeyValueStore::PostgreSQL->new( { table => 'bitly_processing_results' } );
    }
    return $postgresql_stores{ $pid };
}

sub _get_s3_store_for_current_pid()
{
    my $pid = $$;

    unless ( $s3_stores{ $pid } )
    {
        my $config = MediaWords::Util::Config::get_config;
        $s3_stores{ $pid } = MediaWords::KeyValueStore::AmazonS3->new(
            {
                access_key_id     => $config->{ amazon_s3 }->{ bitly_processing_results }->{ access_key_id },
                secret_access_key => $config->{ amazon_s3 }->{ bitly_processing_results }->{ secret_access_key },
                bucket_name       => $config->{ amazon_s3 }->{ bitly_processing_results }->{ bucket_name },
                directory_name    => $config->{ amazon_s3 }->{ bitly_processing_results }->{ directory_name },
            }
        );
    }
    return $s3_stores{ $pid };
}

sub copy_from_postgresql_to_s3()
{
    my $job = shift;

    my $postgresql_store = _get_postgresql_store_for_current_pid();
    my $s3_store         = _get_s3_store_for_current_pid();
    my $stories_id       = $job->{ stories_id };

    say STDERR "Copying story $stories_id...";
    $s3_store->store_content( undef, $stories_id, $postgresql_store->fetch_content( undef, $stories_id ) );

    return { product => 1 };
}

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    my $bw = Parallel::Fork::BossWorkerAsync->new(
        work_handler   => \&copy_from_postgresql_to_s3,
        global_timeout => 10,
        worker_count   => 12,
    );

    say STDERR "Fetching a list of Bit.ly stories...";
    my $bitly_stories = $db->query(
        <<EOF
        SELECT object_id AS stories_id
        FROM bitly_processing_results
        ORDER BY object_id
EOF
    )->hashes;

    my $story_count = scalar( @{ $bitly_stories } );
    my $x           = 1;

    say STDERR "Iterating over $story_count Bit.ly stories...";
    foreach my $bitly_story ( @{ $bitly_stories } )
    {
        my $stories_id = $bitly_story->{ stories_id };

        say STDERR "Enqueueing story $x / $story_count...";
        ++$x;

        $bw->add_work( { stories_id => $stories_id } );
    }

    # Must fetch all the "results" for the whole thing to complete successfully
    say STDERR "Fetching results...";
    while ( $bw->pending() )
    {
        my $ref = $bw->get_result();
        if ( $ref->{ ERROR } )
        {
            die $ref->{ ERROR };
        }
    }

    say STDERR "Finishing up...";
    $bw->shut_down();

    say STDERR "All done.";
}

main();
