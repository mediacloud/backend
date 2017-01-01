package MediaWords::Util::URL;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use MediaWords::Util::Config;
use Inline Python => MediaWords::Util::Config::get_mc_python_dir() . '/mediawords/util/url.py';

use Readonly;
use URI;
use URI::QueryParam;
use Regexp::Common qw /URI/;
use MediaWords::Util::Web;
use URI::Escape;
use List::MoreUtils qw/uniq/;

# Regular expressions for invalid "variants" of the resolved URL
Readonly my @INVALID_URL_VARIANT_REGEXES => (

    # Twitter's "suspended" accounts
    qr#^https?://twitter.com/account/suspended#i,
);

# Fetch the URL, evaluate HTTP / HTML redirects; return URL and data after all
# those redirects; die() on error
sub url_and_data_after_redirects($;$$)
{
    my ( $orig_url, $max_http_redirect, $max_meta_redirect ) = @_;

    unless ( defined $orig_url )
    {
        die "URL is undefined.";
    }

    $orig_url = fix_common_url_mistakes( $orig_url );

    unless ( is_http_url( $orig_url ) )
    {
        die "URL is not HTTP(s): $orig_url";
    }

    my $uri = URI->new( $orig_url )->canonical;

    $max_http_redirect //= 7;
    $max_meta_redirect //= 3;

    my $html = undef;

    for ( my $meta_redirect = 1 ; $meta_redirect <= $max_meta_redirect ; ++$meta_redirect )
    {

        # Do HTTP request to the current URL
        my $ua = MediaWords::Util::Web::UserAgent();

        $ua->max_redirect( $max_http_redirect );

        my $response = $ua->get( $uri->as_string );

        unless ( $response->is_success )
        {
            my @redirects = $response->redirects();
            if ( scalar @redirects + 1 >= $max_http_redirect )
            {
                my @urls_redirected_to;

                my $error_message = "";
                $error_message .= "Number of HTTP redirects ($max_http_redirect) exhausted; redirects:\n";
                foreach my $redirect ( @redirects )
                {
                    push( @urls_redirected_to, $redirect->request()->uri()->canonical->as_string );
                    $error_message .= "* From: " . $redirect->request()->uri()->canonical->as_string . "; ";
                    $error_message .= "to: " . $redirect->header( 'Location' ) . "\n";
                }

                TRACE $error_message;

                # Return the original URL (unless we find a URL being a substring of another URL, see below)
                $uri = URI->new( $orig_url )->canonical;

                # If one of the URLs that we've been redirected to contains another URLencoded URL, assume
                # that we're hitting a paywall and the URLencoded URL is the right one
                @urls_redirected_to = uniq @urls_redirected_to;
                foreach my $url_redirected_to ( @urls_redirected_to )
                {
                    my $encoded_url_redirected_to = uri_escape( $url_redirected_to );

                    if ( my ( $matched_url ) = grep /$encoded_url_redirected_to/, @urls_redirected_to )
                    {
                        TRACE
"Encoded URL $encoded_url_redirected_to is a substring of another URL $matched_url, so I'll assume that $url_redirected_to is the correct one.";
                        $uri = URI->new( $url_redirected_to )->canonical;
                        last;

                    }
                }

            }
            else
            {
                TRACE "Request to " . $uri->as_string . " was unsuccessful: " . $response->status_line;

                # Return the original URL and give up
                $uri = URI->new( $orig_url )->canonical;
            }

            last;
        }

        my $new_uri = $response->request()->uri()->canonical;
        unless ( $uri->eq( $new_uri ) )
        {
            TRACE "New URI: " . $new_uri->as_string;
            $uri = $new_uri;
        }

        # Check if the returned document contains <meta http-equiv="refresh" />
        $html = $response->decoded_content || '';
        my $base_uri = $uri->clone;
        if ( $uri->as_string !~ /\/$/ )
        {
            # In "http://example.com/first/two" URLs, strip the "two" part (but not when it has a trailing slash)
            my @base_uri_path_segments = $base_uri->path_segments;
            pop @base_uri_path_segments;
            $base_uri->path_segments( @base_uri_path_segments );
        }

        my $url_after_meta_redirect = meta_refresh_url_from_html( $html, $base_uri->as_string );
        if ( $url_after_meta_redirect and $uri->as_string ne $url_after_meta_redirect )
        {
            TRACE "URL after <meta /> refresh: $url_after_meta_redirect";
            $uri = URI->new( $url_after_meta_redirect )->canonical;

            # ...and repeat the HTTP redirect cycle here
        }
        else
        {
            # No <meta /> refresh, the current URL is the final one
            last;
        }

    }

    return ( $uri->as_string, $html );
}

# for a given set of stories, get all the stories that are source or target merged stories
# in topic_merged_stories_map.  repeat recursively up to 10 times, or until no new stories are found.
sub _get_merged_stories_ids
{
    my ( $db, $stories_ids, $n ) = @_;

    # "The crazy load was from a query to our topic_merged_stories_ids to get
    # url variants.  It looks like we have some case of many, many merged story
    # pairs that are causing that query to make postgres sit on a cpu for a
    # super long time.  There's no good reason to query for ridiculous numbers
    # of merged stories, so I just abitrarily capped the number of merged story
    # pairs to 20 to prevent this query from running away in the future."
    my $max_stories = 20;

    return [] unless ( @{ $stories_ids } );

    return [ @{ $stories_ids }[ 0 .. $max_stories - 1 ] ] if ( scalar( @{ $stories_ids } ) >= $max_stories );

    my $stories_ids_list = join( ',', @{ $stories_ids } );

    my $merged_stories_ids = $db->query( <<END )->flat;
select distinct target_stories_id, source_stories_id
    from topic_merged_stories_map
    where target_stories_id in ( $stories_ids_list ) or source_stories_id in ( $stories_ids_list )
    limit $max_stories
END

    my $all_stories_ids = [ List::MoreUtils::distinct( @{ $stories_ids }, @{ $merged_stories_ids } ) ];

    $n ||= 0;
    if ( ( $n > 10 ) || ( @{ $stories_ids } == @{ $all_stories_ids } ) || ( @{ $stories_ids } >= $max_stories ) )
    {
        return $all_stories_ids;
    }
    else
    {
        return _get_merged_stories_ids( $db, $all_stories_ids, $n + 1 );
    }
}

# get any alternative urls for the given url from topic_merged_stories or topic_links
sub get_topic_url_variants
{
    my ( $db, $urls ) = @_;

    my $stories_ids = $db->query( "select stories_id from stories where url in (??)", @{ $urls } )->flat;

    my $all_stories_ids = _get_merged_stories_ids( $db, $stories_ids );

    return $urls unless ( @{ $all_stories_ids } );

    my $all_stories_ids_list = join( ',', @{ $all_stories_ids } );

    my $all_urls = $db->query( <<END )->flat;
select distinct url from (
    select redirect_url url from topic_links where ref_stories_id in ( $all_stories_ids_list )
    union
    select url from topic_links where ref_stories_id in( $all_stories_ids_list )
    union
    select url from stories where ref_stories_id in ( $all_stories_ids_list )
) q
    where q is not null
END

    return $all_urls;
}

# Given the URL, return all URL variants that we can think of:
# 1) Normal URL (the one passed as a parameter)
# 2) URL after redirects (i.e., fetch the URL, see if it gets redirected somewhere)
# 3) Canonical URL (after removing #fragments, session IDs, tracking parameters, etc.)
# 4) Canonical URL after redirects (do the redirect check first, then strip the tracking parameters from the URL)
# 5) URL from <link rel="canonical" /> (if any)
# 6) Any alternative URLs from topic_merged_stories or topic_links
sub all_url_variants($$)
{
    my ( $db, $url ) = @_;

    unless ( defined $url )
    {
        die "URL is undefined";
    }

    $url = fix_common_url_mistakes( $url );

    unless ( is_http_url( $url ) )
    {
        my @urls = ( $url );
        return @urls;
    }

    # Get URL after HTTP / HTML redirects
    my ( $url_after_redirects, $data_after_redirects ) = url_and_data_after_redirects( $url );

    my %urls = (

        # Normal URL (don't touch anything)
        'normal' => $url,

        # Normal URL after redirects
        'after_redirects' => $url_after_redirects,

        # Canonical URL
        'normalized' => normalize_url( $url ),

        # Canonical URL after redirects
        'after_redirects_normalized' => normalize_url( $url_after_redirects )
    );

    # If <link rel="canonical" /> is present, try that one too
    if ( defined $data_after_redirects )
    {
        my $url_link_rel_canonical = link_canonical_url_from_html( $data_after_redirects, $url_after_redirects );
        if ( $url_link_rel_canonical )
        {
            TRACE "Found <link rel=\"canonical\" /> for URL $url_after_redirects " .
              "(original URL: $url): $url_link_rel_canonical";

            $urls{ 'after_redirects_canonical' } = $url_link_rel_canonical;
        }
    }

    # If URL gets redirected to the homepage (e.g.
    # http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/ leads
    # to http://www.wired.com/), don't use those redirects
    unless ( is_homepage_url( $url ) )
    {
        foreach my $key ( keys %urls )
        {
            if ( is_homepage_url( $urls{ $key } ) )
            {
                TRACE "URL $url got redirected to $urls{$key} which looks like a homepage, so I'm skipping that.";
                delete $urls{ $key };
            }
        }
    }

    my $distinct_urls = [ List::MoreUtils::distinct( values( %urls ) ) ];

    my $all_urls = get_topic_url_variants( $db, $distinct_urls );

    # Remove URLs that can't be variants of the initial URL
    foreach my $invalid_url_variant_regex ( @INVALID_URL_VARIANT_REGEXES )
    {
        $all_urls = [ grep { !/$invalid_url_variant_regex/ } @{ $all_urls } ];
    }

    return @{ $all_urls };
}

1;
