#!/usr/bin/env perl

use strict;
use warnings;

# test MediaWords::Util::URL::normalize_url_lossy

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use English '-no_match_vars';

use Test::More;
use Test::Deep;

BEGIN
{
    use_ok( 'MediaWords::Util::URL' );
}

sub main
{
    my $tests = [
        [ 'http://nytimes.com',          'http://nytimes.com/' ],
        [ 'http://http://nytimes.com',   'http://nytimes.com/' ],
        [ 'HTTP://nytimes.COM',          'http://nytimes.com/' ],
        [ 'http://beta.foo.com/bar',     'http://foo.com/bar' ],
        [ 'http://archive.org/bar',      'http://archive.org/bar' ],
        [ 'http://m.archive.org/bar',    'http://archive.org/bar' ],
        [ 'http://archive.foo.com/bar',  'http://foo.com/bar' ],
        [ 'http://foo.com/bar#baz',      'http://foo.com/bar' ],
        [ 'http://foo.com/bar/baz//foo', 'http://foo.com/bar/baz/foo' ],
    ];

    for my $test ( @{ $tests } )
    {
        is( MediaWords::Util::URL::normalize_url_lossy( $test->[ 0 ] ), $test->[ 1 ], "$test->[ 0 ] -> $test->[ 1 ]" );
    }

    done_testing();
}

main();
