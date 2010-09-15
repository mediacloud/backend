#!/usr/bin/perl

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
    my $lines = retrieve("$dir/../script_archive/crash_lines");

    MediaWords::Crawler::Extractor::find_auto_excluded_lines($lines);

    exit;

}

main();
