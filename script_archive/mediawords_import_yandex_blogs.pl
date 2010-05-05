#!/usr/bin/perl

# import html from http://blogs.yandex.ru/top/ as media sources / feeds

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Encode;
use HTTP::Request;
use LWP::UserAgent;
use Text::Trim;

use DBIx::Simple::MediaWords;
use Feed::Scrape;
use MediaWords::DB;

use constant COLLECTION_TAG => 'russian_yandex_20100316';

# create a media source from a media url and title
sub create_medium
{
    my ( $medium_url, $medium_name ) = @_;
    
    eval {
        
        my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );
    
        my $medium = $db->query( 'select * from media where url = ?', $medium_url )->hash;
        $medium ||= $db->query( 'select * from media where name = ?', $medium_name )->hash;
        $medium ||= $db->create( 'media', { name => $medium_name, url => $medium_url, moderated => 'true', feeds_added => 'false' } );
    
        my $tag_set = $db->find_or_create( 'tag_sets', { name => 'collection' } );

        my $tag = $db->find_or_create( 'tags', { tag => COLLECTION_TAG, tag_sets_id => $tag_set->{ tag_sets_id } } );
    
        $db->find_or_create( 'media_tags_map', { media_id => $medium->{ media_id }, tags_id => $tag->{ tags_id } } );
    
        print STDERR "added $medium_name, $medium_url\n";
    };
    if ( $@ )
    {
        print STDERR "Error adding $medium_name: $@\n";
    }
}

sub main
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";
    
    my $ua = LWP::UserAgent->new;
    
    for my $i ( 1 .. 20 )
    {
        print "fetching http://blogs.yandex.ru/top/?page=$i\n";
        my $html = $ua->get( "http://blogs.yandex.ru/top/?page=$i" )->decoded_content;
        print "fetched.\n";
        
        while ( $html =~ m~"></a><a href="([^"]*)" title="([^"]*)">~gi )
        {
            my ( $url, $title ) = ( $1, $2 );
            create_medium( $url, $title );
        }
    }    
}

main();  
    
__END__

"></a><a href="http://unab0mber.livejournal.com/" title="Abandon all hope ye who enter here">
