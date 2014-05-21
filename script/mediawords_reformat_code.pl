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
    my $stderr_string;

    #say STDERR "Using $perltidy_config_file";

    my $arguments = join( ' ', @ARGV );
    $arguments = ' -se ' . $arguments;     # append errorfile to stderr
    $arguments = ' -syn ' . $arguments;    # check the syntax

    my $error = Perl::Tidy::perltidy(
        argv       => $arguments,
        perltidyrc => $perltidy_config_file,
        stderr     => \$stderr_string,
    );
    if ( $error or $stderr_string )
    {

        my $message = "Error while tidying file(s): " . join( ' ', @ARGV ) . "\n";
        $message .= "Error return code: $error\n";
        $message .= "Error message: $stderr_string\n";

        die $message;
    }
}

main();

__END__
