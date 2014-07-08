#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use TableCreationUtils;

sub main
{
    TableCreationUtils::add_spider_downloads_from_stdin( 'spider_blog_home', 1 );
}

main();
