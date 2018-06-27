#!/usr/bin/env perl

use strict;
use warnings;

# Safest way to get the directory of the current script: http://stackoverflow.com/a/90721/200603
use File::Basename;
my $dirname = dirname( __FILE__ );

exec( "$dirname/run_fcgi_with_plackup.sh" );
