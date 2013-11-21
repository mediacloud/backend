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
use MediaWords::Crawler::Fetcher;
use DB;
use MediaWords::Util::Web;

my $url =
'http://www.nytimes.com/2013/10/08/business/economy/world-bank-scales-back-east-asia-growth-forecasts.html?partner=rss&emc=rss&_r=0';

sub download_with_crawler
{
    my $db = MediaWords::DB::connect_to_db();

    my $fake_download = { url => $url };

    my $response = MediaWords::Crawler::Fetcher::do_fetch( $fake_download, $db );
    if ( $response->is_redirect )
    {
        say '$response->is_redirect';
    }

    if ( $response->is_success )
    {
        say "repsonse is success";
        print $response->decoded_content;
    }
    else
    {
        print STDERR $response->status_line, "\n";
    }

    say "Got response: $response";

    $DB::single = 2;

}

sub main()
{
    my $responses = MediaWords::Util::Web::ParallelGet( [ $url ] );

    my $response = $responses->[ 0 ];

    if ( $response->is_redirect )
    {
        say '$response->is_redirect';
    }

    if ( $response->is_success )
    {
        say "repsonse is success";
        print $response->decoded_content;
    }
    else
    {
        print STDERR $response->status_line, "\n";
    }

    say "Got response: $response";

}

main();
