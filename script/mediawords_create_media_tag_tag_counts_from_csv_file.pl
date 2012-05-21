#!/usr/bin/env perl

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;
use warnings;
use Getopt::Long;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use TableCreationUtils;

sub create_media_tag_tag_counts_temp_table
{
    my ( $table_space ) = @_;

    my $dbh = MediaWords::DB::connect_to_db()
      || die DBIx::Simple::MediaWords->error;

    print STDERR "creating media_tag_tag_counts_new table \n";

    eval { $dbh->query( "DROP TABLE if exists media_tag_tag_counts_new" ); };

    if ( defined( $table_space ) && $table_space ne '' )
    {
        execute_query(
"create table media_tag_tag_counts_new  (media_id integer NOT NULL, tag_sets_id integer NOT NULL, tags_id integer NOT NULL, tag_tags_id integer NOT NULL, tag_count integer NOT NULL) TABLESPACE $table_space "
        );
    }
    else
    {
        execute_query(
"create table media_tag_tag_counts_new  (media_id integer NOT NULL, tag_sets_id integer NOT NULL, tags_id integer NOT NULL, tag_tags_id integer NOT NULL, tag_count integer NOT NULL)"
        );
    }

    my $now = time();
}

sub main
{

    my $csv_file    = '';
    my $table_space = '';

    GetOptions( 'csv_file=s' => \$csv_file, 'table_space=s' => \$table_space )
      or die "USAGE: ./mediawords_create_media_tag_tag_counts --csv_file=FILE_NAME\n";

    die "USAGE: ./mediawords_create_media_tag_tag_counts --csv_file=FILE_NAME [--table_space tablespace] \n"
      unless $csv_file;

    if ( !( -e $csv_file ) )
    {
        die "File don't exist: $csv_file\n";
    }

    if ( !( -r $csv_file ) )
    {
        die "File is not readable: $csv_file\n";
    }

    if ( $csv_file =~ /\"/ )
    {
        die "Illegal file name '$csv_file'\n";
    }

    print STDERR "starting --  " . localtime() . "\n";

    create_media_tag_tag_counts_temp_table( $table_space );

    (
        system(
'psql -c "COPY media_tag_tag_counts_new(media_id, tags_id, tag_tags_id, tag_sets_id, tag_count) FROM STDIN WITH CSV" < '
              . "\"$csv_file\""
          ) == 0
    ) or die;

    print STDERR "creating indices ... -- " . localtime() . "\n";
    my $now = time();

    execute_query( "create index media_tag_tag_counts_media_and_tag_$now on media_tag_tag_counts_new(media_id, tags_id)" );
    execute_query( "create index media_tag_tag_counts_tag_$now on media_tag_tag_counts_new(tags_id)" );
    execute_query( "create index media_tag_tag_counts_media_$now on media_tag_tag_counts_new(media_id)" );
    print STDERR "replacing table ... -- " . localtime() . "\n";
    eval { execute_query( "drop table media_tag_tag_counts" ) };
    execute_query( "alter table media_tag_tag_counts_new rename to media_tag_tag_counts" ) || die "db error";

    print STDERR "analyzing table ... -- " . localtime() . "\n";
    execute_query( "analyze media_tag_tag_counts" );
    print STDERR "Finished creating media_tag_tag_counts table ... -- " . localtime() . "\n";
}

main();
