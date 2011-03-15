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
use File::Temp qw/ tempfile tempdir /;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Copy;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use MediaWords::Controller::Dashboard;

use Getopt::Long;
use Date::Parse;
use Data::Dumper;
use Carp;
use Dir::Self;
my $_stories_id_window_size = 1000;

# base dir
my $_base_dir = __DIR__ . '/..';

sub get_max_stories_id
{
    my ( $dbh ) = @_;

    my $max_stories_id_row = $dbh->query( "select max(stories_id) as max_id from story_sentence_words" );

    my $max_stories_id = $max_stories_id_row->hash()->{ max_id };

    return $max_stories_id;
}


sub get_min_stories_id
{
    my ( $dbh ) = @_;

    my $min_stories_id_row = $dbh->query( "select min(stories_id) as min_id from story_sentence_words" );

    my $min_stories_id = $min_stories_id_row->hash()->{ min_id };

    return $min_stories_id;
}

sub scroll_stories_id_window
{
    my ( $_stories_id_start, $_stories_id_stop, $max_stories_id ) = @_;

    $_stories_id_start = $_stories_id_stop + 1;
    $_stories_id_stop  = $_stories_id_start + $_stories_id_window_size - 1;

    $_stories_id_stop = min( $_stories_id_stop, $max_stories_id );

    return ( $_stories_id_start, $_stories_id_stop );
}

sub isNonnegativeInteger
{
    my ( $val ) = @_;

    return int( $val ) eq $val;
}

sub dump_story_words
{

    my ( $dbh, $dir, $first_dumped_id, $last_dumped_id ) = @_;

    if ( !defined( $first_dumped_id ) )
    {
        $first_dumped_id = 0;
    }

    if ( !defined( $last_dumped_id ) )
    {
        my $max_stories_id = get_max_stories_id( $dbh );
        $last_dumped_id = $max_stories_id;
    }

    my $file_name = "$dir/story_words_" . $first_dumped_id . "_$last_dumped_id" . ".csv";
    open my $output_file, ">", $file_name
      or die "Can't open $file_name $@";

    Readonly my $select_query => "select stories_id, media_id, publish_day, stem, term, sum(stem_count)  as count from  " .
"   story_sentence_words where stories_id >= ? and stories_id <= ? group by stories_id, media_id, publish_day, stem, term"
      . "   order by stories_id, term                  ";

    $dbh->query_csv_dump( $output_file, " $select_query  limit 0 ", [ 0, 0 ], 1 );

    my $_stories_id_start = $first_dumped_id;
    my $_stories_id_stop  = $_stories_id_start + $_stories_id_window_size;

    while ( $_stories_id_start <= $last_dumped_id )
    {
        $dbh->query_csv_dump( $output_file, " $select_query ", [ $_stories_id_start, $_stories_id_stop ], 0 );

        last if ( $_stories_id_stop ) >= $last_dumped_id;

        ( $_stories_id_start, $_stories_id_stop ) =
          scroll_stories_id_window( $_stories_id_start, $_stories_id_stop, $last_dumped_id );
        print STDERR "story_id windows: $_stories_id_start -- $_stories_id_stop   (max_dumped_id: " . $last_dumped_id .
          ")  -- " .
          localtime() . "\n";

    }

    $dbh->disconnect;

    return [ $first_dumped_id, $last_dumped_id ];
}

sub dump_stories
{
    my ( $dbh, $dir, $first_dumped_id, $last_dumped_id ) = @_;

    my $file_name = "$dir/stories_" . $first_dumped_id . "_$last_dumped_id" . ".csv";
    open my $output_file, ">", "$file_name"
      or die "Can't open $file_name: $@";

    $dbh->query_csv_dump(
        $output_file,
        " select stories_id, media_id, url, guid, title, publish_date, collect_date from stories " .
          "   where stories_id >= ? and stories_id <= ? order by stories_id",
        [ $first_dumped_id, $last_dumped_id ],
        1
    );
}

sub dump_media
{
    my ( $dbh, $dir ) = @_;

    my $file_name = "$dir/media.csv";
    open my $output_file, ">", "$file_name"
      or die "Can't open $file_name: $@";

    $dbh->query_csv_dump( $output_file, " select * from media order by media_id", [], 1 );
}

sub dump_media_sets
{
    my ( $dbh, $dir ) = @_;

    my $file_name = "$dir/media_sets.csv";
    open my $output_file, ">", "$file_name"
      or die "Can't open $file_name: $@";

    $dbh->query_csv_dump( $output_file, "select ms.media_sets_id, ms.name, msmm.media_id
  from media_sets ms, media_sets_media_map msmm
  where ms.media_sets_id = msmm.media_sets_id
    and ms.set_type = 'collection'  order by media_sets_id, media_id", [], 1 );
}

sub _current_date
{
    my $ret = localtime();

    $ret =~ s/ /_/g;

    return $ret;
}

sub _get_time_from_file_name
{
    my ( $file_name ) = @_;

    $file_name =~ /media_.*dump_(.*)_\d+_(\d+)\.zip/;
    my $date = $1;
    $date =~ s/_/ /g;
    return str2time( $date );
}

sub _get_last_story_id_from_file_name
{
    my ( $file_name ) = @_;

    $file_name =~ /media_.*dump_(.*)_\d+_(\d+)\.zip/;
    my $stories_id = $2;

    return $stories_id;
}

sub main
{

    my $incremental;
    my $full;

    my $usage = "mediawprds_dump_story_tables.pl --incremental| --full";
    GetOptions(
        'incremental' => \$incremental,
        'full'        => \$full,
    ) or die "$usage\n";

    die $usage unless $incremental || $full;
    die $usage if $incremental && $full;

    if ( $incremental )
    {
        $full = 0;
    }

    my $config = MediaWords::Util::Config::get_config;

    #my $data_dir = $config->{ mediawords }->{ data_dir };

    my $data_dir = $_base_dir . "/root/include/data_dumps";

    mkdir( $data_dir );

    my $temp_dir = tempdir( DIR => $data_dir, CLEANUP => 1 );

    my $current_date = _current_date();

    my $dump_name;

    if ( $full )
    {
        $dump_name = 'media_word_story_full_dump_';
    }
    else
    {
        $dump_name = 'media_word_story_incremental_dump_';
    }
    $dump_name .= $current_date;

    my $dir = $temp_dir . "/$dump_name";

    mkdir( $dir ) or die "$@";

    my $dbh = MediaWords::DB::connect_to_db;

    my $stories_id_start;

    if ( $full )
    {
	$stories_id_start = get_min_stories_id( $dbh );
    }
    else
    {

        my $existing_dump_files = MediaWords::Controller::Dashboard::get_data_dump_file_list();
        say STDERR Dumper( $existing_dump_files );
        say STDERR Dumper(
            [
                map { $_ . ' -- ' . _get_time_from_file_name( $_ ) . ' ' . _get_last_story_id_from_file_name( $_ ); }
                  @$existing_dump_files
            ]
        );

        #exit;
        my $previous_max = max( map { _get_last_story_id_from_file_name( $_ ); } @$existing_dump_files );

        $stories_id_start = $previous_max + 1;
    }

    my $last_dumped_id = get_max_stories_id( $dbh );

    dump_media( $dbh, $dir );
    dump_media_sets( $dbh, $dir );
    dump_stories( $dbh, $dir, $stories_id_start, $last_dumped_id );

    my $existing_dump_files = MediaWords::Controller::Dashboard::get_data_dump_file_list();
    say STDERR Dumper( $existing_dump_files );
    say STDERR Dumper(
        [
            map { $_ . ' -- ' . _get_time_from_file_name( $_ ) . ' ' . _get_last_story_id_from_file_name( $_ ); }
              @$existing_dump_files
        ]
    );

    #exit;

    my $dumped_stories = dump_story_words( $dbh, $dir, $stories_id_start, $last_dumped_id );

    my $zip = Archive::Zip->new();

    my $dir_member = $zip->addTree( "$temp_dir" );

    # Save the Zip file

    my $dump_zip_file_name = $dump_name . '_' . $dumped_stories->[ 0 ] . '_' . $dumped_stories->[ 1 ];

    my $tmp_zip_file_path = "/$data_dir/tmp_$dump_zip_file_name" . ".zip";
    unless ( $zip->writeToFileNamed( $tmp_zip_file_path ) == AZ_OK )
    {
        die 'write error';
    }

    move( $tmp_zip_file_path, "/$data_dir/$dump_zip_file_name" . ".zip" ) || die "Error renaming file $@";
}

main();
