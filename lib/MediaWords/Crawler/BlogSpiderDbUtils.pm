package MediaWords::Crawler::BlogSpiderDbUtils;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;

# MODULES

use Data::Dumper;
use DateTime;
use Encode;
use Feed::Find;
use HTML::LinkExtractor;
use URI::Split;
use Carp;

use MediaWords::Crawler::Pager;
use MediaWords::Crawler::BlogUrlProcessor;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;
use FindBin;

sub url_in_downloads
{
    my ( $dbs, $url ) = @_;

    my $found_downloads = $dbs->query( "select * from downloads where url = ? limit 1", $url )->hashes;

    if ( scalar( @$found_downloads ) )
    {
        return 1;
    }

    return 0;
}

sub add_friends_list_page
{
    my ( $dbs, $url, $download ) = @_;

    my $friends_list_page = MediaWords::Crawler::BlogUrlProcessor::get_friends_list( $url );

    return if ( !defined( $friends_list_page ) );

    print STDERR "Add spider friends_list_page download '$friends_list_page'\n";

    die "Trying to add null $friends_list_page" unless $friends_list_page;

    return if ( url_in_downloads( $dbs, $friends_list_page ) );

    my $parent;

    if ( defined( $download ) )
    {
        $parent = $download->{ downloads_id };
    }

    $dbs->create(
        'downloads',
        {
            url    => $friends_list_page,
            parent => $parent,
            host   => lc( ( URI::Split::uri_split( $friends_list_page ) )[ 1 ] ),

            type          => 'spider_blog_friends_list',
            sequence      => 0,
            state         => 'pending',
            priority      => 1,
            download_time => 'now()',
            extracted     => 'f'
        }
    );

    return;
}

1;
