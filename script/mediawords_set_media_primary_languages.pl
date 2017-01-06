#!/usr/bin/env perl

# set the primary language field for any media for which it is not set

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $media = $db->query( "select * from media where primary_language is null order by media_id" )->hashes;
    map { MediaWords::DBI::Media::set_primary_language( $db, $_ ) } @{ $media };

}

main();
