#!/usr/bin/env perl

# Carton and pluckup are the recommended way of starting media cloud. So this script has been reproposed to simply exec ./script/run_fcgi_with_plackup_and_carton

# In most cases, this script can be in an Apache config simply by changing the $HOME environment variable for the mediacloud user below.

use strict;
use warnings;

#use Catalyst::ScriptRunner;
#Catalyst::ScriptRunner->run( 'MediaWords', 'FastCGI' );

use File::Spec;
use File::Basename;

#ALTER THIS LINE TO THE HOME DIRECTORY OF THE MEDIACLOUD USER
# $ENV{ HOME } = '/space/mediacloud';

#According to a question on SO, this is a the safest way to get the directory of the current script.
#See http://stackoverflow.com/questions/84932/how-do-i-get-the-full-path-to-a-perl-script-that-is-executing

my $dirname = dirname( __FILE__ );

exec( "$dirname/run_fcgi_with_plackup_and_carton.sh" );

1;
