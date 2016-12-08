#!/usr/bin/env perl

# manually download and handle the given feed.   useful for debugging feed handling issues.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib", "$FindBin::Bin";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;

use MediaWords::Crawler::Engine;
use MediaWords::DB;
use MediaWords::Util::Config qw(get_config);
use MediaWords::Util::URL;

sub create_feed_download
{
    my ( $db, $feed ) = @_;

    my $download = {
        feeds_id  => $feed->{ feeds_id },
        url       => $feed->{ url },
        host      => MediaWords::Util::URL::get_url_host( $feed->{ url } ),
        type      => 'feed',
        sequence  => 1,
        state     => 'fetching',
        priority  => 1,
        extracted => 'f'
    };

    return $db->create( 'downloads', $download );
}

sub main
{
    my ( $feeds_id ) = @ARGV;

    die( "usage: $0 <feed id>" ) unless ( $feeds_id );

    my $dnpf = get_config->{ mediawords }->{ do_not_process_feeds };
    die( "set mediawords.do_not_process_feeds to 'no' in mediawords.yml" ) if ( $dnpf && ( $dnpf eq 'yes' ) );

    my $db = MediaWords::DB::connect_to_db;

    my $feed = $db->find_by_id( 'feeds', $feeds_id );

    die( "Unable to find feed '$feeds_id'" ) unless ( $feed );

    DEBUG "FEED STATE PRE: " . Dumper( $feed );

    my $download = create_feed_download( $db, $feed );

    my $handler = MediaWords::Crawler::Engine::handler_for_download( $db, $download );

    my $response = $handler->fetch_download( $db, $download );

    if ( !$response->is_success )
    {
        $db->query( "update downloads set state = 'error' where downloads_id = ?", $download->{ downloads_id } );
        die( "error fetching download: " . $response->as_string );
    }

    $handler->handle_download( $db, $download, $response->decoded_content );

    $db->query( "update downloads set state = 'success' where downloads_id = ?", $download->{ downloads_id } );

    my $stories = $db->query( <<SQL, $download->{ downloads_id } )->hashes;
select s.*
    from stories s
        join downloads d on ( d.stories_id = s.stories_id )
    where
        d.parent = ?
SQL

    $feed = $db->find_by_id( 'feeds', $feed->{ feeds_id } );

    DEBUG "FEED STATE POST: " . Dumper( $feed );

    DEBUG "ADDED " . scalar( @{ $stories } ) . " STORIES:";

    map { DEBUG "$_->{ title } [$_->{ stories_id }]" } @{ $stories };
}

main();
