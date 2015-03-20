package MediaWords::Util::Paths;

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use File::Spec;
use File::Basename;

#According to a question on SO, this is a the safest way to get the directory of the current script.
#See http://stackoverflow.com/questions/84932/how-do-i-get-the-full-path-to-a-perl-script-that-is-executing
my $_dirname      = dirname( __FILE__ );
my $_dirname_full = File::Spec->rel2abs( $_dirname );

sub mc_root_path
{
    my $root_path = "$_dirname_full/../../../";

    #say STDERR "Root path is $root_path";

    return $root_path;
}

sub mc_script_path
{
    my $root_path = mc_root_path();

    my $script_path = "$root_path/script";

    #say STDERR "script path is $script_path";

    return $script_path;
}

1;
