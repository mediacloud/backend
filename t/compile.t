#!/usr/bin/env perl

use strict;
use warnings;

use File::Find;
use Test::More;

sub main
{

    my $perl_files = [];

    my $wanted = sub { push( @{ $perl_files }, $_ ) if ( $_ =~ /\.p[ml]$/ ); };

    File::Find::find( { wanted => $wanted, no_chdir => 1 }, 'lib' );

    my $ignore_files = { 'lib/MediaWords/MyFCgiManager.pm' => 1 };

    my $modules;
    for my $file ( @{ $perl_files } )
    {
        next if ( $ignore_files->{ $file } );

        # whitelist what can go into the file names to be eval safe
        next if ( $file =~ /[^a-z0-9\-_\.\/]/i );

        # ignore test files
        next if ( $file =~ m~/t/~ );

        # convert file into module name
        $file =~ s~.*lib\/~~;
        $file =~ s~/~::~g;
        $file =~ s~\.p[ml]$~~;

        push( @{ $modules }, $file );
    }

    for my $module ( @{ $modules } )
    {
        eval( "use $module;" );
        ok( !$@, "compile error in $module" );
    }

    done_testing();
}

main();
