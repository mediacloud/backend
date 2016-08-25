#!/usr/bin/env perl

# run this script periodically to add any stories in updated media sources to the solr import queue

use strict;
use warnings;

use Sys::RunAlone;

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

    my $dv_name = 'last_media_solr_import';

    my ( $import_date ) = $db->query( "SELECT NOW()" )->flat;

    my $media =
      $db->query( "select * from media where db_row_last_updated > last_solr_import_date order by media_id" )->hashes;

    my $total_media = scalar( @{ $media } );

    my $i = 0;
    for my $medium ( @{ $media } )
    {
        $i++;
        DEBUG( "$i / $total_media: updating $medium->{ name } [$medium->{ media_id}]" );

        my ( $import_date ) = $db->query( "SELECT NOW()" )->flat;
        $db->query( <<SQL, $medium->{ media_id } );
CREATE TEMPORARY TABLE media_import_stories AS select stories_id from stories where media_id = ?
SQL

        # we do the big query above to a temporary table first because it can be a long running query and we don't
        # want to lock solr_import_extra_stories for long
        $db->begin;
        $db->query( "update media set last_solr_import_date = ? where media_id = ?", $import_date, $medium->{ media_id } );
        $db->query( 'INSERT INTO solr_import_extra_stories SELECT stories_id FROM media_import_stories' );
        $db->commit;

        $db->query( "discard temp" );
    }

}

main();

__END__
