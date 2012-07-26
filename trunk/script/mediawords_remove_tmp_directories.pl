#!/usr/bin/perl

# remove temp directories used by the web app.  this is useful 
# to run when switching users running the web app to avoid permissions errors

use strict;

use File::Path;

sub main 
{
	File::Path::rmtree( '/tmp/mediacloud-session', '/tmp/chi-driver-fastmmap' );
	File::Path::rmtree( '/tmp/chi-driver-fastmmap' );

	print "Content-Type: text/plain\n\n";
	print "done!\n";
}

main();
