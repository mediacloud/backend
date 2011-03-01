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

my $_stories_id_start       = 0;
my $_stories_id_window_size = 1000;
my $_stories_id_stop        = $_stories_id_start + $_stories_id_window_size;

my $_cached_max_stories_id = 0;

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

sub dump_story_words
{

    my ( $dbh, $dir ) = @_;

    my $max_stories_id = get_max_stories_id( $dbh );

    my $file_name = "$dir/story_words.csv";
    open my $output_file, ">", $file_name
      or die "Can't open $file_name $@";

    Readonly my $select_query =>
"select stories_id, media_id, publish_day, stem, term, sum(stem_count)  as count from story_sentence_words where stories_id >= ? and stories_id < ? group by stories_id, media_id, publish_day, stem, term";

    $dbh->query_csv_dump( $output_file, " $select_query  limit 0 ", [ 0, 0 ], 1 );

    while ( $_stories_id_start <= $max_stories_id )
    {
        $dbh->query_csv_dump( $output_file, " $select_query ", [ $_stories_id_start, $_stories_id_stop ], 0 );

        scroll_stories_id_window();
    }

    $dbh->disconnect;
}

sub dump_stories
{
    my ( $dbh, $dir ) = @_;

    my $file_name = "$dir/stories.csv";
    open my $output_file, ">", "$dir/stories.csv"
      or die "Can't open $file_name: $@";

    $dbh->query_csv_dump( $output_file,
        " select stories_id, media_id, url, guid, title, publish_date, collect_date, full_text_rss from stories ",
        [], 1 );
}

sub dump_media
{
    my ( $dbh, $dir ) = @_;

    my $file_name = "$dir/media.csv";
    open my $output_file, ">", "$file_name"
      or die "Can't open $file_name: $@";

    $dbh->query_csv_dump( $output_file, " select * from media ", [], 1 );
}

sub _current_date
{
    my $ret = localtime();

    $ret =~ s/ /_/g;

    return $ret;
}

sub main
{

    my $config   = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_dir };

    my $temp_dir = tempdir( DIR => $data_dir, CLEANUP => 1  );

    my $current_date = _current_date();

    my $dump_name = '/media_word_story_dump_' . "$current_date";
    my $dir       = $temp_dir . "/$dump_name";

    mkdir( $dir ) or die "$@";

    my $dbh = MediaWords::DB::connect_to_db;
    dump_media( $dbh, $dir );
    dump_stories( $dbh, $dir );
    dump_story_words( $dbh, $dir );

    my $zip = Archive::Zip->new();

    my $dir_member = $zip->addTree( "$temp_dir" );

    # Save the Zip file
    unless ( $zip->writeToFileNamed( "/$data_dir/$dump_name" . ".zip" ) == AZ_OK )
    {
        die 'write error';
    }

}

main();
