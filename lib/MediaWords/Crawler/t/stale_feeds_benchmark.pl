#!/usr/bin/perl

use strict;
use warnings;

use Benchmark;

use IPC::Run3;

use MediaWords::DB;
use MediaWords::Util::Config;
use MediaWords::Crawler::Engine;
use MediaWords::Crawler::Provider;
use DBIx::Simple::MediaWords;

sub prepare
{
    my ( $dbs ) = @_;

    my $engine = MediaWords::Crawler::Engine->new();

    # use the test database connection settings
    $engine->dbs( $dbs );

    # prepare the test database
    $dbs->reset_schema();

    #$dbs->commit();
    $dbs->query( "DROP SCHEMA IF EXISTS stories_tags_map_media_sub_tables CASCADE" );

    #$dbs->commit();

    my $script_dir = MediaWords::Util::Config::get_config()->{ mediawords }->{ script_dir };
    $dbs->load_sql_file( "$script_dir/mediawords.sql" );

    #$dbs->commit();

    my $script      = "$script_dir/restore_media_and_feed_information.sh";
    my $db_settings = MediaWords::DB::connect_settings();
    my $type        = $db_settings->{ type };
    my $host        = $db_settings->{ host };
    my $database    = $db_settings->{ db };
    my $username    = $db_settings->{ user };
    my $in          = $db_settings->{ pass } . "\ny\n";

    run3( [ $script_dir . "/run_with_cred.${type}.sh", $script, $host, $database, $username ], \$in );

    return MediaWords::Crawler::Provider->new( $engine );
}

sub time_provide_downloads
{
    my @args = @_;

    my $dbs      = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info( 'test' ) );
    my $provider = prepare( $dbs );

    my $t0 = new Benchmark;
    $provider->provide_downloads( @args );

    #$dbs->commit();
    my $t1 = new Benchmark;
    return timediff( $t1, $t0 );
}

print timestr( time_provide_downloads() ) . "\n";

# you can't do this more than once because of hidden state somewhere... :-( (Provider)
