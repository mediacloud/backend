#!/usr/bin/env perl

# generate a csv of controversy redirects that are not obviously valid

use strict;
use warnings;

use v5.10;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Encode;
use Text::CSV_XS;

use MediaWords::DB;
use MediaWords::DBI::Media;

my $_ignore_redirects = {
    'guardian.co.uk' => 'theguardian.com',
    'vkontakte.ru'   => 'vk.com',
    'newsweek.com'   => 'dailybeast.com',
    'msn.com'        => 'nbcnews.com',
    'iht.com'        => 'nytimes.com',
};

# the redirect is obviously valid if:
# * it is from feedburner or feedproxy
sub redirect_obviously_valid
{
    my ( $db, $link ) = @_;

    my $url_domain = MediaWords::DBI::Media::get_medium_domain( $link );
    my $redirect_url_domain = MediaWords::DBI::Media::get_medium_domain( { url => $link->{ redirect_url } } );

    return 1 if ( $url_domain eq $redirect_url_domain );

    $url_domain =~ /^([^\.]*)/;
    my $url_sld = $1;

    $redirect_url_domain =~ /^([^\.]*)/;
    my $redirect_url_sld = $1;

    return 1 if ( $url_sld && ( length( $url_sld ) > 2 ) && ( $url_sld eq $redirect_url_sld ) );

    return 1 if ( $_ignore_redirects->{ $url_domain } && ( $_ignore_redirects->{ $url_domain } eq $redirect_url_domain ) );

    return 0;
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $links = $db->query( <<END )->hashes;
select cl.* 
    from controversy_links cl
        join cd.live_stories s on ( cl.stories_id = s.stories_id and s.controversies_id = cl.controversies_id )
        join cd.live_stories r on ( cl.ref_stories_id = r.stories_id and r.controversies_id = cl.controversies_id )
    where
        s.media_id <> r.media_id and
        cl.url <> cl.redirect_url and
        ( cl.url not like '%feedburner.com%' ) and
        ( cl.url not like '%feedsportal.com%' ) and
        ( cl.url not like '%feedproxy.com%' ) and
        ( cl.url not like 'http://feed%' ) and
        ( cl.url not like 'http://wp.me%' ) and
        ( cl.url not like 'http://bit.ly%' ) and
        ( cl.url not like 'http://youtu.be%' ) and
        ( cl.url not like 'http://goo.gl%' ) and
        ( cl.url not like 'http://t.co%' ) and
        ( cl.url not like 'http://tinyurl.com%' ) and
        ( cl.url not like 'http://rusnat.com%' ) and
        ( cl.url not like 'http://r.reuters.com%' ) and
        ( cl.url not like '%links.heritage.com%' ) and
        ( cl.url not like 'http://click.icptrack.com%' ) and
        ( cl.url not like '%rd.yahoo.com%' ) and
        lower( substring( cl.url from 1 for 32 ) ) <> lower( substring( cl.redirect_url from 1 for 32 ) )
    order by random()
END

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    my $keys = [ qw(controversy_links_id stories_id url redirect_url ref_stories_id controversies_id) ];

    $csv->combine( @{ $keys } );
    say( $csv->string );

    for my $link ( @{ $links } )
    {
        next if ( redirect_obviously_valid( $db, $link ) );

        $csv->combine( map { $link->{ $_ } } @{ $keys } );
        say( encode( 'utf8', $csv->string ) );
    }
}

main();
