package Feed::Scrape::MediaWords;
use base 'Feed::Scrape';

# subclass of Feed::Scrape that prunes out list of ignored and existing urls

use strict;

use Feed::Scrape;

# local version of get_valid_feeds_from_urls that ignores urls that either exist in our database or match one of the ignore patterns
sub get_valid_feeds_from_urls
{
    my ( $class, $urls, $db, $ignore_patterns_string, $existing_urls ) = @_;

    my $ignore_patterns = [ split( ' ', $ignore_patterns_string ) ];

    my $pruned_urls = [];
    for my $url ( @{ $urls } )
    {
        my $existing_url =
          $db->query( "select f.url, m.name from feeds f, media m " . "  where f.media_id = m.media_id and f.url = ?", $url )
          ->hash;
        if ( $existing_url )
        {

            #print STDERR "EXISTING URL: $existing_url->{ url } [$existing_url->{ name }]\n";
            push( @{ $existing_urls }, "$existing_url->{ url } [$existing_url->{ name }]" );
            next;
        }
        if ( grep { index( lc( $url ), lc( $_ ) ) > -1 } @{ $ignore_patterns } )
        {
            next;
        }

        push( @{ $pruned_urls }, $url );
    }

    return $class->SUPER::get_valid_feeds_from_urls( $pruned_urls );
}

1;
