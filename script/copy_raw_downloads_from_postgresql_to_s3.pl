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

my %db_handles;
my %postgresql_stores;
my %s3_stores;

sub _get_db_handle_for_current_pid()
{
    my $pid = $$;

    unless ( $db_handles{ $pid } )
    {
        $db_handles{ $pid } = MediaWords::DB::connect_to_db();
    }
    return $db_handles{ $pid };
}

sub _get_postgresql_store_for_current_pid()
{
    my $pid = $$;

    unless ( $postgresql_stores{ $pid } )
    {
        $postgresql_stores{ $pid } = MediaWords::KeyValueStore::PostgreSQL->new( { table => 'raw_downloads' } );
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
                access_key_id     => $config->{ amazon_s3 }->{ downloads }->{ access_key_id },
                secret_access_key => $config->{ amazon_s3 }->{ downloads }->{ secret_access_key },
                bucket_name       => $config->{ amazon_s3 }->{ downloads }->{ bucket_name },
                directory_name    => $config->{ amazon_s3 }->{ downloads }->{ directory_name },
            }
        );
    }
    return $s3_stores{ $pid };
}

sub copy_from_postgresql_to_s3()
{
    my $job = shift;

    my $db               = _get_db_handle_for_current_pid();
    my $postgresql_store = _get_postgresql_store_for_current_pid();
    my $s3_store         = _get_s3_store_for_current_pid();
    my $downloads_id     = $job->{ downloads_id };

    INFO "Copying download $downloads_id...";
    $s3_store->store_content( $db, $downloads_id, $postgresql_store->fetch_content( $db, $downloads_id ) );

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

    INFO "Fetching a list of downloads...";
    my $raw_downloads = $db->query(
        <<EOF
        SELECT object_id AS downloads_id
        FROM raw_downloads
        ORDER BY object_id
EOF
    )->hashes;

    my $download_count = scalar( @{ $raw_downloads } );
    my $x              = 1;

    INFO "Iterating over $download_count downloads...";
    foreach my $download ( @{ $raw_downloads } )
    {
        my $downloads_id = $download->{ downloads_id };

        INFO "Enqueueing download $x / $download_count...";
        ++$x;

        $bw->add_work( { downloads_id => $downloads_id } );
    }

    # Must fetch all the "results" for the whole thing to complete successfully
    INFO "Fetching results...";
    while ( $bw->pending() )
    {
        my $ref = $bw->get_result();
        if ( $ref->{ ERROR } )
        {
            LOGCONFESS $ref->{ ERROR };
        }
    }

    INFO "Finishing up...";
    $bw->shut_down();

    INFO "All done.";
}

main();
