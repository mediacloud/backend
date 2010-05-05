package Feed::Scrape::MediaWords;
use base 'Feed::Scrape';

# subclass of Feed::Scrape that prunes out list of ignored and existing urls

use strict;

use Feed::Scrape;

sub get_valid_feeds_from_urls
{
    my ( $class, $urls, $c, $ignore_patterns_string ) = @_;

    my $ignore_patterns = [ split( ' ', $ignore_patterns_string ) ];

    my $pruned_urls = [];
    for my $url ( @{$urls} )
    {
        if ( $c->dbis->query( "select * from feeds where url = lower(?)", $url )->hash )
        {
            next;
        }
        if ( grep { index( lc($url), lc($_) ) > -1 } @{$ignore_patterns} )
        {
            next;
        }

        push( @{$pruned_urls}, $url );
    }

    return $class->SUPER::get_valid_feeds_from_urls($pruned_urls);
}

1;
