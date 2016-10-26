#!/usr/bin/env perl
#
# Carton and plackup are the recommended way of starting Media Cloud.
#

use strict;
use warnings;

# Safest way to get the directory of the current script: http://stackoverflow.com/a/90721/200603
use File::Basename;
my $dirname = dirname( __FILE__ );

exec( "$dirname/run_fcgi_with_plackup_and_carton.sh" );
