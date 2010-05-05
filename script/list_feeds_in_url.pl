#!/usr/bin/perl -w

use Feed::Find;
use Data::Dumper;
use Encode;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Feed::Scrape;

use strict;


my $url = $ARGV[0];

print "$url\n";

 my $ua = LWP::UserAgent->new;

# Create a request
my $req = HTTP::Request->new(GET => $url);

# Pass request to the user agent and get a response back
my $res = $ua->request($req);

# Check the outcome of the response
if ($res->is_success) {
    print 'URL final = ' . $res->request->uri . "\n";
    my $content = $res->content;

    #print Dumper($content);
    
    print "Feed::Find\n";
    print Dumper(Feed::Find->find_in_html(\$content,  $res->request->uri));


    print "Feed::Scrape\n";
    print Dumper(Feed::Scrape->get_feed_urls_from_html( $res->request->uri, $content));
    print "Feed::Scrape valid\n";
    print Dumper(Feed::Scrape->get_valid_feeds_from_html( $res->request->uri, $content));
}
else {
    print $res->status_line, "\n";
}

