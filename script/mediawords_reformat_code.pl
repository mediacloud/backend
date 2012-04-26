#!/bin/sh
#! -*-perl-*-
eval 'exec perl -x -wS $0 ${1+"$@"}'
  if 0;

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use strict;
use warnings;


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
