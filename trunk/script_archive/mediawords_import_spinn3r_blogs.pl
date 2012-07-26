#!/usr/bin/perl

# import list of spinn3r blogs from csv (see csv sample in DATA section below)

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Date::Parse;
use HTTP::Request;
use LWP::UserAgent;
use Text::CSV_XS;
use Text::Trim;

use DBIx::Simple::MediaWords;
use Feed::Scrape;
use MediaWords::DB;

use constant COLLECTION_TAG => 'spinn3r_us_20100407';

# create a media source from a media name and a feed url
sub _create_medium
{
    my ( $medium_url, $feed_url ) = @_;

    my $medium;
    eval {

        my $db = MediaWords::DB::connect_to_db();

        my $response = LWP::UserAgent->new->request( HTTP::Request->new( GET => $feed_url ) );

        if ( !$response->is_success )
        {
            print STDERR "Unable to fetch '$feed_url': " . $response->status_line . "\n";
            return;
        }

        my $feed = Feed::Scrape->parse_feed( $response->decoded_content );

        my $medium_name;
        if ( $feed )
        {
            $medium_name = $feed->title;
        }
        else
        {
            print STDERR "Unable to parse feed '$feed_url'\n";
            $medium_name = $medium_url;
        }

        my $last_post_date = 0;
        if ( $feed && $feed->get_item( 0 ) )
        {
            $last_post_date = Date::Parse::str2time( $feed->get_item( 0 )->pubDate );
        }

        if ( ( time - $last_post_date ) > ( 86400 * 90 ) )
        {
            print STDERR "obsolete feed $medium_name, $medium_url, $feed_url ($last_post_date)\n";
            return;
        }

        if ( $db->query( "select * from media where name = ?", $medium_name )->hash )
        {
            print STDERR "medium '$medium_name' already exists\n";
            return;
        }

        $medium =
          $db->create( 'media', { name => $medium_name, url => $medium_url, moderated => 'true', feeds_added => 'true' } );

        $db->create( 'feeds', { name => $medium_name, url => $feed_url, media_id => $medium->{ media_id } } );

        my $tag_set = $db->find_or_create( 'tag_sets', { name => 'collection' } );

        my $tag = $db->find_or_create( 'tags', { tag => COLLECTION_TAG, tag_sets_id => $tag_set->{ tag_sets_id } } );

        $db->find_or_create( 'media_tags_map', { media_id => $medium->{ media_id }, tags_id => $tag->{ tags_id } } );

        print STDERR "ADDED $medium_name, $medium_url, $feed_url\n";

    };
    if ( $@ )
    {
        print STDERR "Error adding $medium_url: $feed_url: $@\n";
        return;
    }

    return $medium;
}

sub main
{
    my ( $file ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    if ( !$file )
    {
        die( "usage: mediawords_import_spinn3r_blogs.pl <csv file>\n" );
    }

    my $csv = Text::CSV_XS->new( { binary => 1 } ) || die "Cannot use CSV: " . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(utf8)", $file || die "Unable to open file $file: $!\n";

    $csv->column_names( $csv->getline( $fh ) );

    my $media_added = 0;
    while ( my $row = $csv->getline_hr( $fh ) )
    {
        if ( _create_medium( $row->{ source }, $row->{ feedurl } ) )
        {
            print STDERR "BLOGS ADDED: " . ++$media_added . "\n";
        }

        if ( $media_added > 1000 )
        {
            last;
        }
    }
}

main();

__END__
spinn3r_firehose_id,authoremail,authorname,feedhashcode,feedurl,feedresource,guid,lang,link,posttitle,pubdate,published,resourceguid,source,sourcehashcode,title,weblogindegree,weblogpublishertype,weblogtier,weblogtitle
71269335,missioninteract@gmail.com,MI2 7/26-8/1 Kyle,nh3ojoGiYHA,http://missioninteract.blogspot.com/feeds/posts/default,http://missioninteract.blogspot.com/feeds/posts/default,http://missioninteract.blogspot.com/2009/10/he-will-run-race.html,en,http://missioninteract.blogspot.com/2009/10/he-will-run-race.html,He will run the race ...,2009-10-28 05:42:07,2009-10-28 06:06:00,npDkT4h~bRQ,http://missioninteract.blogspot.com/,18g84gOAcNg,He will run the race ...,0,WEBLOG,-1,Mission Interact Oviedo - John 17:21
262669650,noreply@blogger.com,Miss W,pC7UaVrzGps,http://mrscgradblog.blogspot.com/feeds/posts/default,http://mrscgradblog.blogspot.com/feeds/posts/default,http://mrscgradblog.blogspot.com/2009/11/week-3-cedu-534.html,en,http://mrscgradblog.blogspot.com/2009/11/week-3-cedu-534.html,Week 3--CEDU 534,2009-11-15 09:54:02,2009-11-15 09:26:00,RhewdXcQQuw,http://mrscgradblog.blogspot.com/,EqEjulWVqVc,Week 3--CEDU 534,0,WEBLOG,-1,Mrs. C's Grad. Blog
44104430,,katherineed4128,ODmNj~H3ZV8,,,http://katherineed4128.livejournal.com/732.html,en,http://katherineed4128.livejournal.com/732.html,Someone who would appreciate his work. It was true that my interests lay in physics and chemistry ra,2009-10-24 22:26:28,2009-10-24 22:26:27,8MbnSs9KN0M,http://katherineed4128.livejournal.com,HmAz2Vyp3yw,Someone who would appreciate his work. It was true that my interests lay in physics and chemistry ra,-1,WEBLOG,-1,
20255535,,caleyelguero,dory7vruGWM,http://caleyelguero.wordpress.com/feed/,http://caleyelguero.wordpress.com/feed,http://caleyelguero.wordpress.com/2009/10/19/muerto-mania,en,http://caleyelguero.wordpress.com/2009/10/19/muerto-mania/,Muerto-mania,2009-10-22 00:27:21,2009-10-20 00:07:13,yrPrznKYLQA,http://caleyelguero.wordpress.com/,-rdnpYRE1CQ,Muerto-mania,0,WEBLOG,-1,"snapshots of mexico, literal and figurative"
12970877,,Phil Plait,3fiQE8S3V84,http://blogs.discovermagazine.com/badastronomy/feed/,http://blogs.discovermagazine.com/badastronomy/feed,http://blogs.discovermagazine.com/badastronomy/2009/10/20/quick-and-dirties,en,http://blogs.discovermagazine.com/badastronomy/2009/10/20/quick-and-dirties/,Quick and dirties,2009-10-20 20:46:19,2009-10-20 19:44:28,FqBY0kAtcUc,http://www.badastronomy.com/bablog,lHRWpG~I7zo,Quick and dirties,6,WEBLOG,62,Discover Blogs
