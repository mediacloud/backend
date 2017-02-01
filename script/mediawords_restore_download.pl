#!/usr/bin/env perl

# fetch and then restore the content for the specified download.  mostly useful for testing / debugging he content store

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;

sub main
{
    my ( $downloads_id ) = @ARGV;

    die( "usage: $0 <downloads_id>" ) unless ( $downloads_id );

    my $db = MediaWords::DB::connect_to_db;

    my $download = $db->require_by_id( 'downloads', $downloads_id );

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download );

    die( "Unable to get content" ) unless ( $content_ref );

    $download = MediaWords::DBI::Downloads::store_content( $db, $download, $content_ref );
}

main();
