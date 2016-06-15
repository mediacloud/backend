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

use MediaWords::DB;

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    my $dv_name = 'last_media_solr_import';

    my ( $import_date ) = $db->query( "SELECT NOW()" )->flat;

    my ( $last_import_date ) = $db->query( 'SELECT value FROM database_variables WHERE name = ?', $dv_name )->flat;

    if ( !$last_import_date )
    {
        say STDERR "no value found for $dv_name. setting to now";
        $db->create( 'database_variables', { name => $dv_name, value => $import_date } );
        return;
    }

    $db->query(
        <<SQL,
        CREATE TEMPORARY TABLE media_import_stories AS
            SELECT stories_id
            FROM stories s
                JOIN media m
                    ON s.media_id = m.media_id
            WHERE m.db_row_last_updated > \$1 AND
                  s.stories_id NOT IN (
                    SELECT stories_id
                    FROM solr_import_extra_stories
                  )
SQL
        $last_import_date
    );

    # we do the big query above to a temporary table first because it can be a long running query and we don't
    # want to lock solr_import_extra_stories for long
    $db->begin;
    $db->query( 'INSERT INTO solr_import_extra_stories SELECT stories_id FROM media_import_stories' );
    $db->query( "DELETE FROM database_variables WHERE name = ?", $dv_name );
    $db->create( 'database_variables', { name => $dv_name, value => $import_date } );
    $db->commit;

}

main();

__END__
