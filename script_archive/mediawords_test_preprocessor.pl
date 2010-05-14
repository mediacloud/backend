#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;

# do a test run of the text extractor
sub main
{
    my $text;
    while ( <> )
    {
        $text .= $_;
    }

    my $lines = MediaWords::Crawler::Extractor::preprocess( $text );
    print join "\n", @{ $lines };
}

main();
