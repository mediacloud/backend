use strict;
use warnings;

use Test::Deep;
use Test::More;

use MediaWords::DBI::Stories::Dup;

sub test_get_title_parts
{
    cmp_deeply( MediaWords::DBI::Stories::Dup::_get_title_parts( 'foo' ),           [ 'foo' ] );
    cmp_deeply( MediaWords::DBI::Stories::Dup::_get_title_parts( 'FOO: bar' ),      [ 'foo bar', 'foo', 'bar' ] );
    cmp_deeply( MediaWords::DBI::Stories::Dup::_get_title_parts( 'FOO : bar' ),     [ 'foo bar', 'foo', 'bar' ] );
    cmp_deeply( MediaWords::DBI::Stories::Dup::_get_title_parts( 'FOO - bar' ),     [ 'foo bar', 'foo', 'bar' ] );
    cmp_deeply( MediaWords::DBI::Stories::Dup::_get_title_parts( 'FOO | bar' ),     [ 'foo bar', 'foo', 'bar' ] );
    cmp_deeply( MediaWords::DBI::Stories::Dup::_get_title_parts( 'opinion: bar' ),  [ 'bar' ] );
    cmp_deeply( MediaWords::DBI::Stories::Dup::_get_title_parts( 'subject: bar' ),  [ 'bar' ] );
    cmp_deeply( MediaWords::DBI::Stories::Dup::_get_title_parts( 'revealed: bar' ), [ 'bar' ] );
    cmp_deeply(
        MediaWords::DBI::Stories::Dup::_get_title_parts( 'washington post: foo bar' ),
        [ 'washington post foo bar', 'washington post', 'foo bar' ]
    );
    cmp_deeply( MediaWords::DBI::Stories::Dup::_get_title_parts( 'http://foo.com/foo/bar' ), [ 'http://foo.com/foo/bar' ] );
}

sub main()
{
    test_get_title_parts();

    done_testing();
}

main();
