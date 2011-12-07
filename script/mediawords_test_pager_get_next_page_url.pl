#!/usr/bin/perl

# start a daemon that crawls all feeds in the database.
# see MediaWords::Crawler::Engine.pm for details.

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::CommonLibs;
use MediaWords::Crawler::Engine;

sub main
{
    my ( $url, $dump_file ) = @ARGV;

    die unless $url && $dump_file;

    open CONTENT_FILE, "<", $dump_file;

    my $content;

    while ( <CONTENT_FILE> )
    {
        $content .= $_;
    }

    my $dbs = MediaWords::DB::connect_to_db;

    my $validate_url = sub { !$dbs->query( "select 1 from downloads where url = ?", $_[ 0 ] ) };

    my $next_page_url = MediaWords::Crawler::Pager->get_next_page_url( $validate_url, $url, $content );

    say $next_page_url;
}

main();
