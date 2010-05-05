package MediaWords::Crawler::BlogUrlCanonicalizer;

use strict;

# MODULES

use Data::Dumper;
use DateTime;
use Encode;
use Feed::Find;
use HTML::Strip;
use HTML::LinkExtractor;
use IO::Compress::Gzip;
use URI::Split;
use XML::Feed;
use Carp;
use Switch;

use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Feeds;
use MediaWords::Util::Config;

# METHODS

sub get_canonical_blog_url
{
    my ($uri) = @_;

    print "$uri\n";

    my $host = $uri->host;

    my $ret = $uri->canonical;

    if ( ref($ret) )
    {
        $ret = $$ret;
    }

    #remove anchor part if applicable.
    $ret =~ s/#.*$//;

    switch ($host)
    {
        case /\.livejournal\.com/  { $ret = canonicalize_live_journal_url($ret); }
        case /\.ya\.ru/            { $ret = canonicalize_yu_ru_url($ret); }
        case 'blogs.mail.ru'       { $ret = canonicalize_blogs_mail_ru($ret); }
        case 'www.liveinternet.ru' { $ret = canonicalize_liveinternet_ru($ret); }
        case 'www.diary.ru'        { $ret = canonicalize_diary_ru($ret); }
        case 'www.24open.ru'       { $ret = canonicalize_24open_ru($ret); }
    }

    if ( $ret =~ /\/$/ )
    {

        #print "Chopping $ret\n";
        chop($ret);
    }

    #$ret =  encode( 'utf-8', $ret );
    return $ret;
}

#TODO find a regular expression escaper on CPAN so we won't have to \ escape stuff
sub canonicalize_prefix_url
{
    my ( $url, $re_prefix ) = @_;
    print "Before '$url'\n";

    $url =~ s/($re_prefix)\/([^\/?]*).*/\1\/\2/;
    print "After '$url'\n";

    return $url;
}

sub canonicalize_tilda_url
{
    my ($url) = @_;
    print "Before '$url'\n";

    $url =~ s/~([^\/?]*).*/~\1/;
    print "After '$url'\n";

    return $url;
}

sub canonicalize_blogs_mail_ru
{
    my ($url) = @_;

    return canonicalize_prefix_url( $url, 'blogs\.mail\.ru\/mail' );
}

sub canonicalize_diary_ru
{
    my ($url) = @_;

    return canonicalize_tilda_url($url);
}

sub canonicalize_liveinternet_ru
{
    my ($url) = @_;

    return canonicalize_prefix_url( $url, 'www\.liveinternet\.ru\/users' );
}

sub canonicalize_24open_ru
{
    my ($url) = @_;
    print "Before '$url'\n";

    #redirect from blog post to blog home
    $url =~ s/(www\.24open\.ru\/[^\/]*\/blog).*/\1/;

    #redirect from user profile to user's blog
    if ( ( $url =~ /www\.24open\.ru\/[^\/?.]*\/$/ ) || ( $url =~ /www\.24open\.ru\/[^\/?.]*$/ ) )
    {
        print "'$url' matches user profile\n";
        $url =~ s/(www\.24open\.ru\/[^\/]*)/\1\/blog/;
    }

    print "After '$url'\n";

    return $url;
}

sub canonicalize_live_journal_url
{
    my ($url) = @_;

    #For live journal we only care about the user's main page for spidering proposes
    $url =~ s/livejournal.com\/.*/livejournal.com/;

    return $url;
}

sub canonicalize_yu_ru_url
{
    my ($url) = @_;

    print "Before '$url'\n";

    $url =~ s/ya\.ru\/.*/ya.ru/;
    print "After '$url'\n";

    return $url;
}

1;
