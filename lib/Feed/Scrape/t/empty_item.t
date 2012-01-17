use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../../lib";
}

use Dir::Self;
use Data::Dumper;
use DBIx::Simple::MediaWords;
use MediaWords::Util::Tags;
use MediaWords::DB;
use File::Slurp;
use Data::Dumper;
use XML::FeedPP;

use Test::NoWarnings;
use Test::More tests => 2 +1;

use_ok( 'Feed::Scrape::MediaWords' );

sub main()
{
    my $feed_text = read_file('/home/dlarochelle/dev/pristine/mediacloud/trunk/business_reduced.xml');
    #my $feed_text = read_file('/home/dlarochelle/dev/pristine/mediacloud/trunk/empty_item_reduced.xml');

    my $feed;

    $feed = Feed::Scrape::MediaWords->parse_feed( $feed_text );
    #$feed = XML::FeedPP::->new( $feed_text, -type => 'string' );

    die( "Unable to parse feed " ) unless $feed;

    my $items = [ $feed->get_item ];

    my $num_new_stories = 0;

  ITEM:
    for my $item ( @{ $items } )
    {
        my $url  = $item->link() || $item->guid();
        my $guid = $item->guid() || $item->link();
	
	ok( (!$guid) || ! ref ( $guid ) , "GUID is nonscalar " . ($guid ? $guid : '<undefined?') );

	next unless $url || $guid;


	if ($guid && ref ($guid))
	{
	    #print STDERR Dumper ($item);

	    #print "guid: $guid\n";
	    #print Dumper( [ $url, $guid ] );
	    #die "invalid guid " 
	}
    }

}

main();
1;
