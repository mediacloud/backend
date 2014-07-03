use strict;
use warnings;

# test HTTP::HashServer

use English '-no_match_vars';

use List::Util;

use Test::More tests => 903;

BEGIN
{
    use_ok( 'HTTP::HashServer' );
    use_ok( 'MediaWords::Util::Web' );
}

my $_port = 8899;

sub main
{

    my $pages = {};
    for my $i ( 1 .. 50 )
    {
        $pages->{ "/page-$i" }         = { page_num => $i, content  => "page-$i content" };
        $pages->{ "/redirect-$i" }     = { page_num => $i, redirect => "page-$i" };
        $pages->{ "/127-redirect-$i" } = { page_num => $i, redirect => "http://localhost:$_port/page-$i" };
    }

    my $hs = HTTP::HashServer->new( $_port, $pages );

    ok( $hs, 'hashserver object returned' );

    $hs->start();

    my $urls;
    while ( my ( $path, $page ) = each( %{ $pages } ) )
    {
        my $expected_content = "page-$page->{ page_num } content";

        # do localhost twice to make sure cached link downloads work with duplicate urls
        push( @{ $urls }, { url => "http://localhost:$_port$path", page => $page, content => $expected_content } );
        push( @{ $urls }, { url => "http://localhost:$_port$path", page => $page, content => $expected_content } );
        push( @{ $urls }, { url => "http://127.0.0.1:$_port$path", page => $page, content => $expected_content } );
    }

    $urls = [ List::Util::shuffle( @{ $urls } ) ];

    MediaWords::Util::Web::cache_link_downloads( $urls );

    for my $url ( @{ $urls } )
    {
        my $content = MediaWords::Util::Web::get_cached_link_download( $url );
        chomp( $content );
        is( $content, $url->{ content }, "$url->{ url } content matches" );
        is( $url->{ _cached_link_downloads }, 1, "$url->{ url } downloaded exactly once" );
    }

    $hs->stop();
}

main();
