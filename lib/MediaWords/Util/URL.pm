package MediaWords::Util::URL;

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use URI;
use Regexp::Common qw /URI/;

# do some simple transformations on a URL to make it match other equivalent
# URLs as well as possible; normalization is "lossy" (makes the whole URL lowercase)
sub normalize_url_lossy($)
{
    my $url = shift;

    $url = lc( $url );

    # r2.ly redirects through the hostname, ala http://543.r2.ly
    if ( $url !~ /r2\.ly/ )
    {
        $url =~ s/^(https?:\/\/)(m|media|data|image|www|cdn|topic|article|news|archive|blog|video|\d+?).?\./$1/i;
    }

    $url =~ s/\#.*//;

    $url =~ s/\/+$//;

    # fix broken urls that look like this: http://http://www.al-monitor.com/pulse
    $url =~ s~(https?)://https?:?//~$1://~i;

    return scalar( URI->new( $url )->canonical );
}

# get the domain of the given url
sub get_url_domain($)
{
    my $url = shift;

    $url =~ m~https?://([^/#]*)~ || return $url;

    my $host = $1;

    my $name_parts = [ split( /\./, $host ) ];

    my $n = @{ $name_parts } - 1;

    my $domain;
    if ( $host =~ /\.(gov|org|com?)\...$/i )
    {
        $domain = join( ".", ( $name_parts->[ $n - 2 ], $name_parts->[ $n - 1 ], $name_parts->[ $n ] ) );
    }
    elsif ( $host =~ /\.(edu|gov)$/i )
    {
        $domain = join( ".", ( $name_parts->[ $n - 2 ], $name_parts->[ $n - 1 ] ) );
    }
    elsif ( $host =~
        /wordpress.com|blogspot|livejournal.com|privet.ru|wikia.com|feedburner.com|24open.ru|patch.com|tumblr.com/i )
    {
        $domain = $host;
    }
    else
    {
        $domain = join( ".", $name_parts->[ $n - 1 ], $name_parts->[ $n ] );
    }

    return lc( $domain );
}

# From the provided HTML, determine the <meta http-equiv="refresh" /> URL (if any)
sub meta_refresh_url_from_html($;$)
{
    my ( $html, $base_url ) = @_;

    my $url = undef;
    while ( $html =~ m~(<\s*?meta.+?>)~gi )
    {
        my $meta_element = $1;

        if ( $meta_element =~ m~http-equiv\s*?=\s*?["']\s*?refresh\s*?["']~i )
        {
            if ( $meta_element =~ m~content\s*?=\s*?["']\d+?\s*?;\s*?URL\s*?=\s*?(.+?)["']~i )
            {
                $url = $1;
                if ( $url )
                {
                    if ( $url !~ /$RE{URI}/ )
                    {
                        # Maybe it's relative / absolute path?
                        if ( $base_url )
                        {
                            my $uri = URI->new_abs( $url, $base_url );
                            return $uri->as_string;
                        }
                        else
                        {
                            say STDERR
                              "HTML <meta http-equiv=\"refresh\"/> found, but the new URL ($url) doesn't seem to be valid.";
                        }
                    }
                    else
                    {
                        # Looks like URL, so return it
                        return $url;
                    }
                }
            }
        }
    }

    return undef;
}

# From the provided HTML, determine the <link rel="canonical" /> URL (if any)
sub link_canonical_url_from_html($;$)
{
    my ( $html, $base_url ) = @_;

    my $url = undef;
    while ( $html =~ m~(<\s*?link.+?>)~gi )
    {
        my $link_element = $1;

        if ( $link_element =~ m~rel\s*?=\s*?["']\s*?canonical\s*?["']~i )
        {
            if ( $link_element =~ m~href\s*?=\s*?["'](.+?)["']~i )
            {
                $url = $1;
                if ( $url )
                {
                    if ( $url !~ /$RE{URI}/ )
                    {
                        # Maybe it's absolute path?
                        if ( $base_url )
                        {
                            my $uri = URI->new_abs( $url, $base_url );
                            return $uri->as_string;
                        }
                        else
                        {
                            say STDERR
                              "HTML <link rel=\"canonical\"/> found, but the new URL ($url) doesn't seem to be valid.";
                        }
                    }
                    else
                    {
                        # Looks like URL, so return it
                        return $url;
                    }
                }
            }
        }
    }

    return undef;
}

1;
