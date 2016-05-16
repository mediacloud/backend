#!/usr/bin/env perl

# feedly import gave us a bunch of old dead wapo urls that look like this:
#    http://feeds.washingtonpost.com/c/34656/f/636686/s/3564bcbb/sc/35/l/0L0Swashingtonpost0N0Cblogs0Cearly0Elead0Cwp0C20A140C0A10C0A10Cjohnny0Emanziel0Eunreal0Ein0Etexas0Eam0Ecomeback0Evideo0C/story01.htm
#
# this script attempts to revive the urls by plucking the direct wapo url out of the feed url

package script::mediawords_fix_wapo_urls;

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Util::Web;

my $_decode_feed_map =
{
    '0A' => '0',
    '0B' => '.',
    '0C' => '/',
    '0E' => '-',
    '0I' => '_',
};


sub decode_feed
{
    my ( $a ) = @_;

    my $b = $_decode_feed_map->{ $a };

    LOGDIE( "Unable to decode '$a'" ) unless ( defined( $b ) );

    return $b;
}

sub transform_url
{
    if ( $_[ 1 ]->( $_[ 0 ] ) )
    {
        TRACE( "transform url $_[ 2 ]:\n\t$_[ 0 ]" );
        return 1;
    }

    WARN( "transform url $_[ 2 ]: FAIL for\n\t$_[ 0 ]" );
    return 0;
}

sub valid_url
{
    my ( $url ) = @_;

    my $ua = MediaWords::Util::Web::UserAgent;

    my $response = $ua->get( $url );

    if ( $response->is_success )
    {
        TRACE( "test_url SUCCESS:\n\t$url" );
        return 1;
    }
    else
    {
        TRACE( "test_url FAILE:\n\t$url" );
        return 0;
    }
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $downloads = $db->query( <<SQL )->hashes;
select d.*
    from downloads d
        join feeds f on ( d.feeds_id = f.feeds_id )
    where
        f.media_id = 2 and
        f.name = 'MediaWords::ImportStories::Feedly' and
        d.state = 'error'
    --order by md5( d.downloads_id::text ) limit 10

SQL

    my $failed_downloads = [];
    my $skipped_downloads = [];

    my $i = 0;

    $db->begin;

    for my $download ( @{ $downloads } )
    {
        eval
        {
            my $url = $download->{ url };

            DEBUG( sub { "download $download->{ downloads_id } [ story $download->{ stories_id } ]" } );

            DEBUG( sub { "broken url:\n\t$url" } ) ;

            if ( $url =~ /express0C0J/ )
            {
                push( @{ $skipped_downloads }, $download );
                DEBUG( "SKIP" );
                next;
            }

            next unless (
                transform_url( $url, sub { $_[0] =~ s/.*washingtonpost0N0C// } , "wp prefix" ) ||
                transform_url( $url, sub { $_[0] =~ s/.*posteverything0Bwashpost0N0C/posteverything0C/ } , "pe prefix" )
            );

            next unless ( transform_url( $url, sub { $_[0] =~ s/(0Dwprss0Frss0I.*)?\/story01.htm// } , "story suffix" ) );

            next unless ( transform_url( $url, sub { $_[0] =~ s/(0.)/decode_feed( $1 )/eg }, "decode" ) );

            $url = "http://www.washingtonpost.com/$url";

            DEBUG( sub { "fixed url:\n\t$url" } );

            $download->{ fixed_url } = $url;

            $db->query( <<SQL, $download->{ downloads_id }, $url );
update downloads set url = \$2, state = 'pending', error_message = null where downloads_id = \$1
SQL

            $db->query( <<SQL, $download->{ stories_id }, $url );
update stories set url = \$2 where stories_id= \$1
SQL

            # push( @{ $failed_downloads }, $download )if ( !valid_url( $url ) )
        };

        if ( $@ )
        {
            push( @{ $failed_downloads }, $download );
            WARN( "error processing download: $@\n" . Dumper( $download ) );
        }

        if ( !( ++$i % 100 ) )
        {
            $db->commit;
            $db->begin;
        }
    }

    $db->commit;

    say "skipped downloads: " . Dumper( map { $_->{ url } } @{ $skipped_downloads } );
    # say "failed downloads: " .
    #     Dumper( map { { url => $_->{ url }, fixed_url => $_->{ fixed_url } } } @{ $failed_downloads } );
}

main();
