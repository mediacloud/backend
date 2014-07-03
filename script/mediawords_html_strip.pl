#!/usr/bin/env perl

#Runs html_strip on the concat'ed input and prints the results.

use strict;
use warnings;

my $dir;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    $dir = $FindBin::Bin;
}

use MediaWords::Crawler::Extractor;

use Storable;

sub main
{

    my $html;
    while ( <> )
    {
        $html .= $_;
    }

    print( MediaWords::Util::HTML::html_strip( $html ) );

    exit;

}

main();
