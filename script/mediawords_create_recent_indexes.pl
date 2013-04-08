#!/usr/bin/env perl

# drop and recreate key indexes to include only recent entries to improve index lookup speed.
# as our core downloads and stories tables have grown, basic index retrieval time has increased to 200-300ms,
# which slows down systems like the crawler a lot.  Partitioning those tables would solve the problem but
# require a lot more complexity.  We get most of the benefit of partitioning by just periodically recreating
# key indexes for only recent entries for those tables.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2012";

use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::Util::SQL;

# if pending downloads are greater than this number, do not reindex because it will take a long time
# and lock the tables.  The recent indexes are fast enough even with millions of entries.
use constant MAX_PENDING_DOWNLOADS => 10000;

# drop the index if it already exists
sub drop_index_if_exists
{
    my ( $db, $index ) = @_;

    my ( $index_exists ) = $db->query( "select 1 from pg_class where relname = ?", $index )->flat;

    return unless ( $index_exists );

    $db->query( "drop index $index" );
}

# drop and recreate an index with the given name, table, fields, and predicate.
# if predicate is a number, assume a predicate of 'table_id >= $predicate'
sub recreate_index
{
    my ( $db, $name, $table, $fields, $predicate ) = @_;

    say STDERR "recreating $name ...";

    die( "only indexes ending in _recent are allowed" ) unless ( $name =~ /_recent$/ );

    drop_index_if_exists( $db, $name );

    $predicate = "${ table }_id >= $predicate" if ( $predicate =~ /^\d+$/ );

    my $query = "create index $name on $table ( $fields ) where $predicate";

    say STDERR $query;

    $db->query( $query );
}

sub main
{
    my $db = MediaWords::DB::connect_to_db;

    # use a limit in this query so it doesn't take forever when there are lots of pending downloads
    my ( $pending_downloads ) = $db->query( <<END, MAX_PENDING_DOWNLOADS + 1 )->flat;
select count(*) from ( select 1 from downloads where state = 'pending' limit ? ) q
END

    if ( $pending_downloads > MAX_PENDING_DOWNLOADS )
    {
        say STDERR "Refusing to recreate indexes because there are more than " . MAX_PENDING_DOWNLOADS .
          " pending downloads";
        return;
    }

    my ( $min_downloads_id ) = $db->query( "select min( downloads_id ) from downloads where state = 'pending'" )->flat;
    $min_downloads_id ||= 0;

    recreate_index( $db, 'downloads_downloads_id_recent', 'downloads', 'downloads_id', $min_downloads_id );

    my ( $min_stories_id ) = $db->query( "select min( stories_id ) from downloads where state = 'pending'" )->flat;
    $min_stories_id ||= 0;

    # in theory, we might end up with a very small stories_id and try to reindex the whole stories table, which
    # would lock up the database, so just guess if the stories_id is too low
    my ( $max_stories_id ) = $db->query( "select max( stories_id ) from stories" )->flat;
    $max_stories_id ||= 0;

    if ( ( $max_stories_id - $min_stories_id ) > ( MAX_PENDING_DOWNLOADS * 10 ) )
    {
        $min_stories_id = $max_stories_id - MAX_PENDING_DOWNLOADS;
    }

    recreate_index( $db, 'stories_stories_id_recent', 'stories', 'stories_id', $min_stories_id );

    # use the past day for the predicate since these queries don't include the stories_id
    my $now       = MediaWords::Util::SQL::get_sql_date_from_epoch( time() );
    my $yesterday = "publish_date > '$now'::date - '1 day'::interval";
    
    recreate_index( $db, 'stories_guid_recent', 'stories', 'guid, media_id', $yesterday ); 
    recreate_index( $db, 'stories_title_pubdate_recent', 'stories', 'title, publish_date', $yesterday );

}

main();
