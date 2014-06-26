#!/usr/bin/env perl

use 5.14.2;

use strict;
use warnings;

use File::Basename 'dirname';
use File::Spec;

my $script_dir = dirname( File::Spec->rel2abs( __FILE__ ) );
chdir( "$script_dir/.." );

use Cwd;

#say getcwd;

use Carton::CLI;

my $mediacloud_fastcgi_script = "$script_dir/mediawords_fastcgi.pl";

Carton::CLI->new->run( 'exec', '--', $mediacloud_fastcgi_script, $@ );
