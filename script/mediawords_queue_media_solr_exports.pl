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

    my ( $import_date ) = $db->query( "select now()" )->flat;

    my ( $last_import_date ) = $db->query( "select value from database_variables where name = ?", $dv_name )->flat;

    if ( !$last_import_date )
    {
        say STDERR "no value found for $dv_name.  setting to now";
        $db->create( 'database_variables', { name => $dv_name, value => $import_date } );
        return;
    }

    $db->query( <<SQL, $last_import_date );
create temporary table media_import_stories as
    select stories_id
        from stories s
            join media m on ( s.media_id = m.media_id )
        where
            m.db_row_last_updated > \$1 and
            s.stories_id not in ( select stories_id from solr_import_stories )
SQL

    # we do the big query above to a temporary table first because it can be a long running query and we don't
    # want to lock solr_import_stories for long
    $db->begin;
    $db->query( "insert into solr_import_stories select stories_id from media_import_stories" );
    $db->query( "delete from database_variables where name = ?", $dv_name );
    $db->create( 'database_variables', { name => $dv_name, value => $import_date } );
    $db->commit;

}

main();

__END__
