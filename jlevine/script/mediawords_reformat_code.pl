#!/usr/bin/perl

# import list of spidered russian blogs from csv

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use strict;
use warnings;

use Perl6::Say;
use Data::Dumper;
use Perl::Tidy 20090616;

sub main
{

    Perl::Tidy::perltidy(
        argv       => \@ARGV,
        perltidyrc => "$FindBin::Bin/mediawords_perltidy_config_file"
    );
}

main();

__END__
