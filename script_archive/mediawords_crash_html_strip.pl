#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

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
    my $line = ${ retrieve( "$dir/../script_archive/crash_line" ) };

    #my $line = $lines->[0];

    ( MediaWords::Util::HTML::html_strip( $line ) );

    exit;

}

main();
