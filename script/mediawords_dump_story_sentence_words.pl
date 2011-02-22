#!/usr/bin/perl -w

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
use DBIx::Simple::MediaWords;
use TableCreationUtils;
use Readonly;

my $_stories_id_start       = 0;
my $_stories_id_window_size = 1000;
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

# sub add_sub_table_indexes
# {
#     for ( my $media_id = 0 ; $media_id < scalar( @_existing_media_sub_tables ) ; $media_id++ )
#     {
#         if ( defined $_existing_media_sub_tables[ $media_id ] )
#         {
#             MediaWords::DBI::StoriesTagsMapMediaSubtables::create_indexes_for_sub_table( $media_id );
#         }
#     }
# }

sub query_csv_dump
{
    my ( $db, $output_file, $query, $params, $with_header ) = @_;

    my $copy_statement = "COPY ($query) TO STDOUT WITH CSV ";

    if ( $with_header )
    {
        $copy_statement .= " HEADER";
    }

    my $line;
    $db->dbh->do( $copy_statement, {}, @$params );
    while ( $db->dbh->pg_getcopydata( $line ) >= 0 )
    {
        print $output_file $line;
    }

}

sub main
{

    my $dbh = MediaWords::DB::connect_to_db;

    my $max_stories_id = get_max_stories_id( $dbh );

    open my $output_file, ">", "/tmp/story_words.csv";

    my $select_query =
"select stories_id, media_id, publish_day, stem, term, sum(stem_count)  as count from story_sentence_words where stories_id >= ? and stories_id < ? group by stories_id, media_id, publish_day, stem, term";

    query_csv_dump( $dbh, $output_file, " $select_query  limit 0 ", [ 0, 0 ], 1 );

    while ( $_stories_id_start <= $max_stories_id )
    {
        query_csv_dump( $dbh, $output_file, " $select_query ", [ $_stories_id_start, $_stories_id_stop ], 0 );

        #   $dbh->query( 'INSERT INTO  story_words_temp ' . $select_query , $_stories_id_start, $_stories_id_stop );
        scroll_stories_id_window();
    }

    $dbh->disconnect;
}

main();
