package MediaWords::Util::Web::UserAgent::HTMLRedirects;

#
# Implements various ways to to HTML redirects
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use MediaWords::Util::HTML;
use MediaWords::Util::URL;
use MediaWords::Util::Web::UserAgent::Request;
use HTML::TreeBuilder::LibXML;

# Given a url and content from one of the following url archiving sites, return a request for the original url
sub target_request_from_meta_refresh_url($$)
{
    my ( $content, $archive_site_url ) = @_;

    my $target_url = MediaWords::Util::HTML::meta_refresh_url_from_html( $content, $archive_site_url );
    unless ( $target_url )
    {
        return undef;
    }

    return MediaWords::Util::Web::UserAgent::Request->new( 'GET', $target_url );
}

# Given a url and content from one of the following url archiving sites, return a request for the original url
sub target_request_from_archive_org_url($$)
{
    my ( $content, $archive_site_url ) = @_;

    if ( $archive_site_url =~ m|^https?://web\.archive\.org/web/(\d+?/)?(https?://.+?)$|i )
    {
        my $target_url = $2;
        return MediaWords::Util::Web::UserAgent::Request->new( 'GET', $target_url );
    }

    return undef;
}

sub target_request_from_archive_is_url($$)
{
    my ( $content, $archive_site_url ) = @_;

    if ( $archive_site_url =~ m|^https?://archive\.is/(.+?)$|i )
    {
        my $canonical_link = MediaWords::Util::HTML::link_canonical_url_from_html( $content );
        if ( $canonical_link =~ m|^https?://archive\.is/\d+?/(https?://.+?)$|i )
        {
            my $target_url = $1;
            return MediaWords::Util::Web::UserAgent::Request->new( 'GET', $target_url );
        }
        else
        {
            ERROR "Unable to parse original URL from archive.is response '$archive_site_url': $canonical_link";
        }
    }

    return undef;
}

# given the content of a linkis.com web page, find the original url in the content, which may be in one of
# serveral places in the DOM, and return a request for said URL
sub target_request_from_linkis_com_url($$)
{
    my ( $content, $archive_site_url ) = @_;

    if ( $archive_site_url =~ m|^https?://[^/]*linkis.com/| )
    {
        my $html_tree = HTML::TreeBuilder::LibXML->new;
        $html_tree->ignore_unknown( 0 );
        $html_tree->parse_content( $content );

        my $found_url = 0;

        # list of dom search patterns to find nodes with a url and the
        # attributes to use from those nodes as the url.
        #
        # for instance the first item matches:
        #
        #     <meta property="og:url" content="http://foo.bar">
        #
        my $dom_maps = [
            [ '//meta[@property="og:url"]',        'content' ],
            [ '//a[@class="js-youtube-ln-event"]', 'href' ],
            [ '//iframe[@id="source_site"]',       'src' ],
        ];

        for my $dom_map ( @{ $dom_maps } )
        {
            my ( $dom_pattern, $url_attribute ) = @{ $dom_map };

            my @nodes      = $html_tree->findnodes( $dom_pattern );
            my $first_node = shift @nodes;

            if ( $first_node )
            {
                my $url = $first_node->attr( $url_attribute );
                if ( $url !~ m|^https?://linkis.com| )
                {
                    return MediaWords::Util::Web::UserAgent::Request->new( 'GET', $url );
                }
            }
        }

        # as a last resort, look for the longUrl key in a javascript array
        if ( $content =~ m|"longUrl":\s*"([^"]+)"| )
        {
            my $url = $1;

            # kludge to de-escape \'d characters in javascript -- 99% of urls
            # are captured by the dom stuff above, we shouldn't get to this
            # point often
            $url =~ s/\\//g;

            if ( $url !~ m|^https?://linkis.com| )
            {
                return MediaWords::Util::Web::UserAgent::Request->new( 'GET', $url );
            }
        }

        WARN( "no url found for linkis url: $archive_site_url" );
    }

    return undef;
}

1;
