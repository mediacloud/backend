#!/usr/bin/env perl
#
# Prints Perl version to use, either:
# * a version number to install via Perlbrew, or
# * "system" for the Perlbrew to use system's Perl
#

use strict;
use warnings;

use version 0.77;    # get latest bug-fixes and API;

# Min. Perl version to use

my $perl_min_version;
if ( $ENV{ 'CI' } )
{
    $perl_min_version = '5.22.0';    # Travis CI
}
else
{
    $perl_min_version = '5.22.1';
}

sub main()
{
    my $current_perl_version = substr( $^V, 1 );

    if ( version->parse( $current_perl_version ) >= version->parse( $perl_min_version ) )
    {
        print "system\n";
    }
    else
    {
        print "$perl_min_version\n";
    }
}

main();
