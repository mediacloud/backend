#!/usr/bin/env perl

# manually download and handle the given feed.   useful for debugging feed handling issues.

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib", "$FindBin::Bin";
}

use Data::Dumper;
use Modern::Perl "2013";

use MediaWords::Crawler::Fetcher;
use MediaWords::Crawler::FeedHandler;
use MediaWords::DB;
use MediaWords::Util::Config qw(get_config);

sub create_feed_download
{
    my ( $db, $feed ) = @_;

    my $download = {
        feeds_id  => $feed->{ feeds_id },
        url       => $feed->{ url },
        host      => lc( ( URI::Split::uri_split( $feed->{ url } ) )[ 1 ] ),
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

    say STDERR "FEED STATE PRE: " . Dumper( $feed );

    my $download = create_feed_download( $db, $feed );

    my $response = MediaWords::Crawler::Fetcher::do_fetch( $download, $db );

    if ( !$response->is_success )
    {
        $db->query( "update downloads set state = 'error' where downloads_id = ?", $download->{ downloads_id } );
        die( "error fetching download: " . $response->as_string );
    }

    MediaWords::Crawler::FeedHandler::handle_feed_content( $db, $download, $response->decoded_content );
    $db->query( "update downloads set state = 'success' where downloads_id = ?", $download->{ downloads_id } );

    my $stories = $db->query( <<SQL, $download->{ downloads_id } )->hashes;
select s.*
    from stories s
        join downloads d on ( d.stories_id = s.stories_id )
    where
        d.parent = ?
SQL

    say STDERR "FEED STATE POST: " . Dumper( $feed );

    say STDERR "ADDED " . scalar( @{ $stories } ) . " STORIES:";

    map { say STDERR "$_->{ title } [$_->{ stories_id }]" } @{ $stories };
}

main();
