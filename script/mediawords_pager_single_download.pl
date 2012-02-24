#!/usr/bin/env perl

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
    my ( $downloads_id ) = @ARGV;

    die unless $downloads_id;

    my $dbs = MediaWords::DB::connect_to_db;

    my $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (?)", $downloads_id )->hashes;

    my $download = pop @{ $downloads };

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $download );

    my $validate_url = sub { !$dbs->query( "select 1 from downloads where url = ?", $_[ 0 ] ) };

    my $next_page_url = MediaWords::Crawler::Pager->get_next_page_url( $validate_url, $download->{ url }, $$content_ref );

    say $next_page_url;
}

main();
