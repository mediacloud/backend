#!/usr/bin/env perl

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use MediaWords::DB;
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use MediaWords::DBI::StoriesTagsMapMediaSubtables;
use TableCreationUtils;
use Readonly;
use Term::Prompt;

my $_stories_id_start       = 0000000;
my $_stories_id_window_size = 25000;
my $_stories_id_stop        = $_stories_id_start + $_stories_id_window_size;
my $_cached_max_stories_id  = 0;

sub get_max_stories_id
{
    my ( $dbh ) = @_;

    my $max_stories_id_row = $dbh->query( "select max(stories_id) as max_id from stories" );

    my $max_stories_id = $max_stories_id_row->hash()->{ max_id };

    $_cached_max_stories_id = $max_stories_id;

    return $max_stories_id;
}

sub scroll_stories_id_window
{
    $_stories_id_start = $_stories_id_stop;
    $_stories_id_stop  = $_stories_id_start + $_stories_id_window_size;

    print STDERR "story_id windows: $_stories_id_start -- $_stories_id_stop   (max_stories_id: " . $_cached_max_stories_id .
      ")  -- " .
      localtime() . "\n";
}

sub get_rows_in_stories_id_window
{
    my ( $dbh ) = @_;

    print STDERR "starting fetching rows in window $_stories_id_start - $_stories_id_stop  ... -- " . localtime() . "\n";

    my $rows = $dbh->query(
"select media_id, publish_date, stories_tags_map.*, tags.tag_sets_id from (select media_id, publish_date, stories_id from stories where stories.stories_id < ? and stories.stories_id >= ? and stories.publish_date > (now() - interval ' 90 days')) as stories, stories_tags_map, tags where stories_tags_map.tags_id=tags.tags_id and stories.stories_id=stories_tags_map.stories_id   and stories_tags_map.stories_id < ? and stories_tags_map.stories_id >= ?  order by stories.stories_id",
        $_stories_id_stop, $_stories_id_start, $_stories_id_stop, $_stories_id_start );

    print STDERR "finished fetching rows in window ... -- " . localtime() . "\n";

    return $rows;
}

my @_existing_media_sub_tables;

sub exists_media_id_sub_table
{
    my ( $media_id ) = @_;

    if ( defined( $_existing_media_sub_tables[ $media_id ] ) )
    {
        return 1;
    }

    return 0;
}

sub get_sub_table_name_for_media_id
{
    my ( $media_id ) = @_;

    return MediaWords::DBI::StoriesTagsMapMediaSubtables::get_or_create_sub_table_name_for_media_id( $media_id );
}

sub isNonnegativeInteger
{
    my ( $val ) = @_;

    return int( $val ) eq $val;
}

sub create_foreign_key_query_string
{
    my ( $altered_table, $referenced_table, $referenced_column ) = @_;

    my $query =
      " ALTER TABLE ONLY $altered_table " . ' ADD CONSTRAINT ' . $altered_table . '_fkey_' . $referenced_column .
      ' FOREIGN KEY (' . $referenced_column . ')' . ' REFERENCES ' . " $referenced_table($referenced_column) " .
      ' ON DELETE CASCADE ';

    return $query;
}

sub create_foreign_key
{
    my ( $altered_table, $referenced_table, $referenced_column ) = @_;

    my $foreign_key_query = create_foreign_key_query_string( $altered_table, $referenced_table, $referenced_column );

    execute_query( $foreign_key_query );
}

sub add_sub_table_indexes
{
    for ( my $media_id = 0 ; $media_id < scalar( @_existing_media_sub_tables ) ; $media_id++ )
    {
        if ( defined $_existing_media_sub_tables[ $media_id ] )
        {
            MediaWords::DBI::StoriesTagsMapMediaSubtables::create_indexes_for_sub_table( $media_id );
        }
    }
}

sub main

{
    print STDERR "Running this script is generally unnecessary.\n";
    print STDERR "This script will recreate the stories_tags_map_media_sub_tables schema and tables.\n";
    print STDERR "However, these tables are now automatically updated by the extractor.\n";
    print STDERR "\nWARNING: DO NOT RUN THIS SCRIPT WHEN THE EXTRACTOR IS RUNNING. THIS MAY CORRUPT YOUR DATABASE\n";
    print STDERR "\n";

    my $result = &prompt( "y", "Are you sure you wish to continue?", "", "n" );

    exit unless ( $result );

    my $dbh = MediaWords::DB::connect_to_db()
      || die DBIx::Simple::MediaWords->error;

    MediaWords::DBI::StoriesTagsMapMediaSubtables::recreate_schema( $dbh );

    my $max_stories_id = get_max_stories_id( $dbh );

    while ( $_stories_id_start <= $max_stories_id )
    {
        my $rows_to_insert = get_rows_in_stories_id_window( $dbh );

        $rows_to_insert->bind( my ( $media_id, $publish_date, $stories_tag_map_id, $stories_id, $tags_id, $tag_sets_id ) );

        my $rows_fetched_in_batch = 0;

        $dbh->begin_work;
        while ( $rows_to_insert->fetch )
        {
            $rows_fetched_in_batch++;

            if ( ( $rows_fetched_in_batch % 5000 ) == 0 )
            {
                print STDERR "fetched $rows_fetched_in_batch in current batch -- " . localtime() . "\n";
                print STDERR "processing stories_id $stories_id (current batch goes until $_stories_id_stop -- " .
                  localtime() . "\n";
            }

            if ( !exists_media_id_sub_table( $media_id ) )
            {
                $dbh->commit;
                MediaWords::DBI::StoriesTagsMapMediaSubtables::get_or_create_sub_table_name_for_media_id( $media_id, 1 );
                $_existing_media_sub_tables[ $media_id ] = 1;
                $dbh->begin_work;
            }

            $dbh->query( 'INSERT INTO ' . get_sub_table_name_for_media_id( $media_id ) .
                  '  (media_id, publish_date, stories_id, tags_id, tag_sets_id) VALUES (?,?,?,?,?)',
                $media_id, $publish_date, $stories_id, $tags_id, $tag_sets_id );
        }

        $dbh->commit;

        scroll_stories_id_window();
    }

    $dbh->disconnect;

    add_sub_table_indexes();

    print STDERR "Sucessfully added all subtables -- " . localtime() . "\n";

}

main();
