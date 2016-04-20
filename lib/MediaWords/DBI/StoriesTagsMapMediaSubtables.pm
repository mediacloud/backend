package MediaWords::DBI::StoriesTagsMapMediaSubtables;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

# various helper functions for downloads

use strict;

use File::Path;
use HTTP::Request;
use Readonly;
use List::MoreUtils qw(any);
use MediaWords::DB;
use MediaWords::Util::Config;
use Carp;

Readonly my $_tag_tag_schema => 'stories_tags_map_media_sub_tables';

sub get_tag_tag_schema
{
    return $_tag_tag_schema;
}

sub recreate_schema
{
    my ( $dbh ) = @_;
    my $_tag_tag_schema = get_tag_tag_schema();
    $dbh->query( "DROP SCHEMA IF EXISTS $_tag_tag_schema CASCADE" );
    $dbh->query( "CREATE SCHEMA $_tag_tag_schema" );
}

sub list_contains
{
    ( my $value, my $list ) = @_;

    return any { $_ eq $value } @{ $list };
}

sub get_media_ids_with_subtables
{
    my ( $db ) = @_;

    my $media_id_rows = $db->query( "SELECT DISTINCT(media_id) from media" );

    my @all_media_ids = @{ $media_id_rows->flat };

    my $sub_table_schema_name = get_tag_tag_schema();
    my @sub_table_names =
      @{ $db->query( "select tablename from pg_tables where schemaname = ?", $sub_table_schema_name )->flat };

    @sub_table_names = map { "$sub_table_schema_name.$_" } @sub_table_names;

    #print join ",\n", map { "'$_'" } @sub_table_names;

    my @media_ids = grep { list_contains( _get_sub_table_full_name_for_media_id( $_ ), \@sub_table_names ) } @all_media_ids;

    #print join ",\n", map { "'$_'" } @media_ids;
    return @media_ids;

}

sub _get_sub_table_base_name_for_media_id
{
    my ( $media_id ) = @_;
    die unless isNonnegativeInteger( $media_id );

    return "stories_tags_map_media_id_$media_id";
}

sub _get_sub_table_full_name_for_media_id
{
    my ( $media_id ) = @_;
    die unless isNonnegativeInteger( $media_id );

    return get_tag_tag_schema() . "." . _get_sub_table_base_name_for_media_id( $media_id );
}

my $_sub_table_names = [];

sub get_media_ids
{
    my $db = MediaWords::DB::connect_to_db;

    my $media_id_rows = $db->query( "SELECT DISTINCT(media_id) from media" );

    my @all_media_ids = @{ $media_id_rows->flat };

    my $sub_table_schema_name = 'stories_tags_map_media_sub_tables';
    my @sub_table_names =
      @{ $db->query( "select tablename from pg_tables where schemaname = ?", $sub_table_schema_name )->flat };

    @sub_table_names = map { "$sub_table_schema_name.$_" } @sub_table_names;

    #print join ",\n", map { "'$_'" } @sub_table_names;

    my @media_ids = grep { list_contains( _get_sub_table_full_name_for_media_id( $_ ), \@sub_table_names ) } @all_media_ids;

    #print join ",\n", map { "'$_'" } @media_ids;
    return @media_ids;
}

sub sub_table_exists
{
    my ( $media_id ) = @_;

    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    my $sub_table_schema_name = 'stories_tags_map_media_sub_tables';
    my @sub_table_names       = @{
        $db->query(
            "select tablename from pg_tables where schemaname = ? and tablename = ? ",
            $sub_table_schema_name,
            _get_sub_table_base_name_for_media_id( $media_id )
        )->flat
    };

    return scalar( @sub_table_names ) > 0;
}

sub get_or_create_sub_table_name_for_media_id
{
    my ( $media_id, $dont_create_indexes ) = @_;

    $dont_create_indexes ||= 0;

    die unless isNonnegativeInteger( $media_id );

    if ( !defined( $_sub_table_names->[ $media_id ] ) )
    {
        if ( !sub_table_exists( $media_id ) )
        {
            create_sub_table_for_media_id( $media_id, $dont_create_indexes );
        }

        my $sub_table_name = _get_sub_table_full_name_for_media_id( $media_id );
        $_sub_table_names->[ $media_id ] = $sub_table_name;
    }

    return $_sub_table_names->[ $media_id ];
}

sub isNonnegativeInteger
{
    my ( $val ) = @_;

    return int( $val ) eq $val && $val > 0;
}

sub execute_query
{
    my ( $dbh, $query ) = @_;

    print STDERR "Starting to execute query: \"$query\"  -- " . localtime() . "\n";

    $dbh->query( $query );

    print STDERR "Finished executing query: \"$query\"  -- " . localtime() . "\n";
}

sub create_indexes_for_sub_table
{
    my ( $media_id ) = @_;

    print STDERR "create)indexes_for_sub_table  -- " . localtime() . "\n";

    my $dbh = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    confess unless isNonnegativeInteger( $media_id );

    my $table_name = _get_sub_table_full_name_for_media_id( $media_id );

    #create_foreign_key( $table_name, 'stories', 'stories_id' );
    #create_foreign_key( $table_name, 'tags',    'tags_id' );
    #create_foreign_key( $table_name, 'media',   'media_id' );

    my $index_name_prefix = $table_name;

    #remove the schema part from the table name to save space
    my $schema = get_tag_tag_schema();
    $index_name_prefix =~ s/^$schema\.//;
    $index_name_prefix =~ s/\./_/;

    execute_query( $dbh, "CREATE INDEX $index_name_prefix" . "_tags_id ON $table_name USING btree (tags_id)" );
    execute_query( $dbh, "CREATE INDEX $index_name_prefix" . "_stories_id ON $table_name USING btree (stories_id)" );
    execute_query( $dbh,
        "CREATE UNIQUE INDEX $index_name_prefix" . "_stories_id_tags_id ON $table_name (stories_id, tags_id)" );
    execute_query( $dbh, "CREATE INDEX $index_name_prefix" . "_publish_date ON $table_name USING btree (publish_date)" );
    execute_query( $dbh,
        "ALTER TABLE ONLY $table_name  ADD CONSTRAINT $index_name_prefix" .
          "_valid_media_id " . " CHECK (media_id=$media_id);" );
}

sub create_sub_table_for_media_id
{
    my ( $media_id, $dont_create_indexes ) = @_;
    $dont_create_indexes ||= 0;

    die unless isNonnegativeInteger( $media_id );

    my $dbh = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      || die DBIx::Simple::MediaWords->error;

    my $stories_tags_media_sub_table = _get_sub_table_full_name_for_media_id( $media_id );

    print STDERR "CREATING TABLE  -- " . '' . $stories_tags_media_sub_table . ' ' . localtime() . "\n";

    print STDERR 'START DROP TABLE if exists ' . $stories_tags_media_sub_table . ' ' . localtime() . "\n";

    {
        my $old_handler = $SIG{ __WARN__ };

        $SIG{ __WARN__ } = 'IGNORE';
        $dbh->query( 'DROP TABLE if exists ' . $stories_tags_media_sub_table );

        $SIG{ __WARN__ } = $old_handler;
    }

    print STDERR 'FINISH DROP TABLE if exists ' . $stories_tags_media_sub_table . ' ' . localtime() . "\n";

    print STDERR 'START CREATE ' . $stories_tags_media_sub_table . ' ' . localtime() . "\n";

    $dbh->query_only_warn_on_error( 'CREATE TABLE ' . ' ' . $stories_tags_media_sub_table .
          ' ( ' . ' media_id integer not null, ' . ' publish_date timestamp without time zone not null, ' .
          ' stories_id integer not null, ' . ' tags_id integer not null,' . ' tag_sets_id integer not null' . ' )' );

    print STDERR "FINISHED CREATING TABLE  -- " . '' . $stories_tags_media_sub_table . ' ' . localtime() . "\n";

    if ( !$dont_create_indexes )
    {
        create_indexes_for_sub_table( $media_id );
    }
}
