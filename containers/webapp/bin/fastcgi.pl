#!/usr/bin/env perl

use strict;
use warnings;

exec( "plackup -I lib -s FCGI --nproc 0 --manager MediaWords::MyFCgiManager" );
