use strict;
use warnings;
use utf8;

use Test::More tests => 11;
use Test::NoWarnings;

use Text::Trim;
use Test::Deep;

use MediaWords::Util::Web::UserAgent::HTMLRedirects;

sub test_target_request_from_meta_refresh_url()
{
    is(
        MediaWords::Util::Web::UserAgent::HTMLRedirects::target_request_from_meta_refresh_url(
            <<EOF,
        <HTML>
        <HEAD>
            <TITLE>This is a test</TITLE>
            <META HTTP-EQUIV="content-type" CONTENT="text/html; charset=UTF-8">
            <META HTTP-EQUIV="refresh" CONTENT="0; URL=http://example.com/">
        </HEAD>
        <BODY>
            <P>This is a test.</P>
        </BODY>
        </HTML>
EOF
            'http://example2.com/'
          )->url(),
        'http://example.com/',
        '<meta> refresh'
    );
}

sub test_target_request_from_archive_is_url()
{
    is(
        MediaWords::Util::Web::UserAgent::HTMLRedirects::target_request_from_archive_is_url(
            '<link rel="canonical" href="https://archive.is/20170201/https://bar.com/foo/bar">',    #
            'https://archive.is/20170201/https://bar.com/foo/bar'                                   #
          )->url(),
        'https://bar.com/foo/bar',                                                                  #
        'archive.is'                                                                                #
    );

    is(
        MediaWords::Util::Web::UserAgent::HTMLRedirects::target_request_from_archive_is_url(
            '<link rel="canonical" href="https://archive.is/20170201/https://bar.com/foo/bar">',    #
            'https://bar.com/foo/bar'                                                               #
        ),
        undef,                                                                                      #
        'archive.is with non-matching URL'                                                          #
    );
}

sub test_target_request_from_archive_org_url()
{
    is(
        MediaWords::Util::Web::UserAgent::HTMLRedirects::target_request_from_archive_org_url(
            undef,                                                                                     #
            'https://web.archive.org/web/20150204024130/http://www.john-daly.com/hockey/hockey.htm'    #
          )->url(),
        'http://www.john-daly.com/hockey/hockey.htm',                                                  #
        'archive.org'                                                                                  #
    );

    is(
        MediaWords::Util::Web::UserAgent::HTMLRedirects::target_request_from_archive_org_url(
            undef,                                                                                     #
            'http://www.john-daly.com/hockey/hockey.htm'                                               #
        ),
        undef,                                                                                         #
        'archive.org with non-matching URL'                                                            #
    );
}

sub test_target_request_from_linkis_com_url()
{
    is(
        MediaWords::Util::Web::UserAgent::HTMLRedirects::target_request_from_linkis_com_url(
            '<meta property="og:url" content="http://og.url/test"',                                    #
            'https://linkis.com/foo.com/ASDF'                                                          #
          )->url(),
        'http://og.url/test',                                                                          #
        'linkis.com <meta>'                                                                            #
    );

    is(
        MediaWords::Util::Web::UserAgent::HTMLRedirects::target_request_from_linkis_com_url(
            '<a class="js-youtube-ln-event" href="http://you.tube/test"',                              #
            'https://linkis.com/foo.com/ASDF'                                                          #
          )->url(),
        'http://you.tube/test',                                                                        #
        'linkis.com YouTube'                                                                           #
    );

    is(
        MediaWords::Util::Web::UserAgent::HTMLRedirects::target_request_from_linkis_com_url(
            '<iframe id="source_site" src="http://source.site/test"',                                  #
            'https://linkis.com/foo.com/ASDF'                                                          #
          )->url(),
        'http://source.site/test',                                                                     #
        'linkis.com <iframe>'                                                                          #
    );

    is(
        MediaWords::Util::Web::UserAgent::HTMLRedirects::target_request_from_linkis_com_url(
            '"longUrl":"http:\/\/java.script\/test"',                                                  #
            'https://linkis.com/foo.com/ASDF'                                                          #
          )->url(),
        'http://java.script/test',                                                                     #
        'linkis.com JavaScript'                                                                        #
    );

    is(
        MediaWords::Util::Web::UserAgent::HTMLRedirects::target_request_from_linkis_com_url(
            '<meta property="og:url" content="http://og.url/test"',                                    #
            'https://bar.com/foo/bar'                                                                  #
        ),
        undef,                                                                                         #
        'linkis.com with non-matching URL'                                                             #
    );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_target_request_from_meta_refresh_url();
    test_target_request_from_archive_is_url();
    test_target_request_from_archive_org_url();
    test_target_request_from_linkis_com_url();
}

main();
