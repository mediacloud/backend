package MediaWords::Util::URL::Variants;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

use Readonly;
use Regexp::Common qw /URI/;
use URI::Escape;
use URI::QueryParam;
use URI;

use MediaWords::Util::HTML;
use MediaWords::Util::URL;
use MediaWords::Util::Web;

# Regular expressions for invalid "variants" of the resolved URL
Readonly my @INVALID_URL_VARIANT_REGEXES => (

    # Twitter's "suspended" accounts
    qr#^https?://twitter.com/account/suspended#i,
);

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
sub _get_topic_url_variants
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
    select url from stories where stories_id in ( $all_stories_ids_list )
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

    $url = MediaWords::Util::URL::fix_common_url_mistakes( $url );

    unless ( MediaWords::Util::URL::is_http_url( $url ) )
    {
        my @urls = ( $url );
        return @urls;
    }

    # Get URL after HTTP / HTML redirects
    my $ua                   = MediaWords::Util::Web::UserAgent->new();
    my $response             = $ua->get_follow_http_html_redirects( $url );
    my $url_after_redirects  = $response->request()->url();
    my $data_after_redirects = $response->decoded_content();

    my %urls = (

        # Normal URL (don't touch anything)
        'normal' => $url,

        # Normal URL after redirects
        'after_redirects' => $url_after_redirects,

        # Canonical URL
        'normalized' => MediaWords::Util::URL::normalize_url( $url ),

        # Canonical URL after redirects
        'after_redirects_normalized' => MediaWords::Util::URL::normalize_url( $url_after_redirects )
    );

    # If <link rel="canonical" /> is present, try that one too
    if ( defined $data_after_redirects )
    {
        my $url_link_rel_canonical =
          MediaWords::Util::HTML::link_canonical_url_from_html( $data_after_redirects, $url_after_redirects );
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
    unless ( MediaWords::Util::URL::is_homepage_url( $url ) )
    {
        foreach my $key ( keys %urls )
        {
            if ( MediaWords::Util::URL::is_homepage_url( $urls{ $key } ) )
            {
                TRACE "URL $url got redirected to $urls{$key} which looks like a homepage, so I'm skipping that.";
                delete $urls{ $key };
            }
        }
    }

    my $distinct_urls = [ List::MoreUtils::distinct( values( %urls ) ) ];

    my $all_urls = _get_topic_url_variants( $db, $distinct_urls );

    # Remove URLs that can't be variants of the initial URL
    foreach my $invalid_url_variant_regex ( @INVALID_URL_VARIANT_REGEXES )
    {
        $all_urls = [ grep { !/$invalid_url_variant_regex/ } @{ $all_urls } ];
    }

    return @{ $all_urls };
}

1;
