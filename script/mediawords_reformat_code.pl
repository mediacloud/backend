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
use MediaWords::Util::Paths;

sub main
{

    my $perltidy_config_file = MediaWords::Util::Paths::mc_script_path() . '/mediawords_perltidy_config_file';

    #say STDERR "Using $perltidy_config_file";

    Perl::Tidy::perltidy(
        argv       => \@ARGV,
        perltidyrc => $perltidy_config_file,
    );
}

main();

__END__
