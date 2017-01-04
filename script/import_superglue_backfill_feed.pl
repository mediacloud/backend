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
use MediaWords::Crawler::Engine;
use MediaWords::Util::URL;

use Data::Dumper;
use Getopt::Long;
use Readonly;

sub import_superglue_backfill_feed($$$$)
{
    my ( $db, $media_id, $feed_name, $feed_url ) = @_;

    Readonly my $superglue_tag_set_name => 'collection';
    Readonly my $superglue_tag_name     => 'superglue';

    $db->begin;

    my ( $feed_exists ) = $db->query(
        <<SQL,
        SELECT 1
        FROM feeds
        WHERE media_id = ?
          AND lower(url) = lower(?)
SQL
        $media_id, $feed_url
    )->flat;
    if ( $feed_exists )
    {
        LOGCONFESS "Feed with URL '$feed_url' already exists in media ID $media_id.";
    }

    INFO "Creating feed with name '$feed_name', URL '$feed_url' for media ID $media_id...";
    my $feed = $db->create(
        'feeds',
        {
            media_id    => $media_id,
            name        => $feed_name,
            url         => $feed_url,
            feed_type   => 'superglue',
            feed_status => 'active',      # will deactivate after backfilling
        }
    );
    my $feeds_id = $feed->{ feeds_id };
    INFO "Created feed $feeds_id";

    INFO "Adding '$superglue_tag_set_name:$superglue_tag_name' to feed $feeds_id...";
    my $tag_set = $db->find_or_create( 'tag_sets', { name => $superglue_tag_set_name } );
    my $tag = $db->find_or_create( 'tags', { tag => $superglue_tag_name, tag_sets_id => $tag_set->{ tag_sets_id } } );
    $db->find_or_create( 'feeds_tags_map', { tags_id => $tag->{ tags_id }, feeds_id => $feeds_id } );

    INFO "Creating download row to be able to download the feed...";
    my $download = $db->create(
        'downloads',
        {
            feeds_id => $feeds_id,
            url      => $feed_url,
            host     => MediaWords::Util::URL::get_url_host( $feed_url ),
            type     => 'feed',
            state    => 'pending',
            priority => 0,
            sequence => 1,
        }
    );
    my $downloads_id = $download->{ downloads_id };
    INFO "Created download $downloads_id";

    my $handler = MediaWords::Crawler::Engine::handler_for_download( $db, $download );

    INFO "Fetching feed $feeds_id as download $downloads_id...";
    my $response = $handler->fetch_download( $db, $download );

    INFO "Handling feed's $feeds_id response for download $downloads_id...";
    $handler->handle_response( $db, $download, $response );

    $download = $db->find_by_id( 'downloads', $download->{ downloads_id } );
    unless ( $download->{ state } eq 'success' )
    {
        LOGCONFESS "Feed's $feeds_id download $downloads_id failed: " . Dumper( $download );
    }

    INFO "Disabling feed $feeds_id so that crawler won't refetch it...";
    $db->update_by_id( 'feeds', $feeds_id, { 'feed_status' => 'inactive', } );

    INFO "Done!";

    $db->commit;
}

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Readonly my $usage => <<"EOF";
Usage: $0 \
    --media_id media_id_to_import_to \
    --feed_name feed_name_to_import 
    --feed_url feed_url_to_import
EOF

    my ( $media_id, $feed_name, $feed_url );
    Getopt::Long::GetOptions(
        'media_id:i'  => \$media_id,
        'feed_name:s' => \$feed_name,
        'feed_url:s'  => \$feed_url,
    ) or die $usage;
    unless ( $media_id and $feed_name and $feed_url )
    {
        die $usage;
    }

    my $db = MediaWords::DB::connect_to_db;

    import_superglue_backfill_feed( $db, $media_id, $feed_name, $feed_url );
}

main();
