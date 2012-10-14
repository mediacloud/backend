#!/usr/bin/env perl

# fill in empty dashboards_id field in queries table by assuming that any
# query with a set of media_sets_ids that matches the media_sets_ids within
# a dashboard should be associatd with that dashboard.
#
# also fill in md5_signature field for each query by calling MediaWords::DBI::Queries::get_md5_signature

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;
use MediaWords::DBI::Queries;

my $_dashboard_media_sets_hash;

sub get_dashboards_media_sets_hash
{
    my ( $media_sets_ids ) = @_;

    my $h = join( '|', sort { $a <=> $b } @{ $media_sets_ids } );

    return $h;
}

sub get_dashboard_media_sets_hash
{
    my ( $db ) = @_;

    my $dashboard_media_sets_vals = {};

    my $dashboard_media_sets = $db->query(
        "select dms.* from dashboard_media_sets dms, media_sets ms " .
          "  where dms.media_sets_id = ms.media_sets_id and ms.set_type = 'collection'",
    )->hashes;

    for my $dms ( @{ $dashboard_media_sets } )
    {
        push( @{ $dashboard_media_sets_vals->{ $dms->{ dashboards_id } } }, $dms->{ media_sets_id } );
    }

    my $dashboard_media_sets_hash = {};
    while ( my ( $dashboards_id, $media_sets_ids ) = each( %{ $dashboard_media_sets_vals } ) )
    {
        $dashboard_media_sets_hash->{ get_dashboards_media_sets_hash( $media_sets_ids ) } = $dashboards_id;
    }

    return $dashboard_media_sets_hash;
}

sub add_query_dashboard
{
    my ( $db, $query ) = @_;

    $_dashboard_media_sets_hash ||= get_dashboard_media_sets_hash( $db );

    my $dashboards_id = $_dashboard_media_sets_hash->{ get_dashboards_media_sets_hash( $query->{ media_sets_ids } ) };

    return unless ( $dashboards_id );

    # print STDERR "query [ $query->{ queries_id } ]: $dashboards_id\n";

    $db->query( "update queries set dashboards_id = ? where queries_id = ?", $dashboards_id, $query->{ queries_id } );
}

sub add_query_signature
{
    my ( $db, $query ) = @_;

    my $md5_signature = MediaWords::DBI::Queries::get_md5_signature( $query );

    # print STDERR "query [ $query->{ queries_id } ]: $md5_signature\n";

    $db->query( "update queries set md5_signature = ? where queries_id = ?", $md5_signature, $query->{ queries_id } );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $queries =
      $db->query( "select * from queries where dashboards_id is null or md5_signature is null order by queries_id" )->hashes;

    my $i = 1;
    for my $query ( @{ $queries } )
    {
        print STDERR "progress: " . $i++ . " / " . @{ $queries } . " \n" unless ( $i % 100 );
        $query->{ media_sets_ids } =
          $db->query( "select media_sets_id from queries_media_sets_map where queries_id = ?", $query->{ queries_id } )
          ->flat;
        $query->{ dashboard_topics_ids } =
          $db->query( "select dashboard_topics_id from queries_dashboard_topics_map where queries_id = ?",
            $query->{ queries_id } )->flat;

        add_query_dashboard( $db, $query ) unless ( $query->{ dashboards_id } );
        add_query_signature( $db, $query ) unless ( $query->{ md5_signature } );
    }
}

main();
