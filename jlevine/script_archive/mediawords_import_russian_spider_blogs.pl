#!/usr/bin/perl

# import list of spidered russian blogs from csv

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

use constant COLLECTION_TAG => 'Russian Random Blogs';

# create a media source from a media name and a feed url
sub _create_medium
{
    my ( $medium_url, $feed_url ) = @_;

    my $medium;
    eval {

        my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

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
        die( "usage: mediawords_import_russian_spider_blogs.pl <csv file>\n" );
    }

    my $csv = Text::CSV_XS->new( { binary => 1 } ) || die "Cannot use CSV: " . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(utf8)", $file || die "Unable to open file $file: $!\n";

    $csv->column_names( $csv->getline( $fh ) );

    my $media_added = 0;
    while ( my $row = $csv->getline_hr( $fh ) )
    {
        if ( _create_medium( $row->{ url }, $row->{ rss } ) )
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
found_blogs_id,site,url,title,rss
1253830,mail.ru,http://blogs.mail.ru/mail/8fluffy8,Áëîãè@Mail.Ru: Ïîçèòèâàÿ Ëèçêà Öâåòêîâà,http://blogs.mail.ru/mail/8fluffy8/?rss=1
1653046,ya.ru,http://buzya8.ya.ru,buzya8 - Ñ.ÑÑ,http://buzya8.ya.ru/rss/posts.xml
245255,liveinternet.ru,http://www.liveinternet.ru/users/gullehhaey,Äíåâíèê gullehhaey : LiveInternet - Ðîññèéñêèé Ñåðâèñ Îíëàéí-Äíåâíèêîâ,http://www.liveinternet.ru/users/gullehhaey/rss/
1641667,rambler.ru,http://planeta.rambler.ru/users/virus-hell,Ïëàíåòà > Ïëàíåòà Þðèê 1974,http://planeta.rambler.ru/users/virus-hell/rss/
594290,liveinternet.ru,http://www.liveinternet.ru/users/1565135,...ÿ ñèëüíàÿ...ÿ ñïðàâëþñü...è âñå-òàêè ÿ ñàìàÿ ñ÷àñòëèâàÿ) : LiveInternet - Ðîññèéñêèé Ñåðâèñ Îíëàéí-Äíåâíèêîâ,http://www.liveinternet.ru/users/1565135/rss/
