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

sub dump_story_words
{

    my ($dbh) = @_;


    my $max_stories_id = get_max_stories_id( $dbh );

    open my $output_file, ">", "/tmp/story_words.csv";

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
   my ($dbh) = @_;

    open my $output_file, ">", "/tmp/stories.csv";

   $dbh->query_csv_dump ( $output_file, " select stories_id, media_id, url, guid, title, publish_date, collect_date, full_text_rss from stories ", [], 1);
}

sub main
{
    my $dbh = MediaWords::DB::connect_to_db;
    dump_stories( $dbh );
    #dump_story_words( $dbh );
}

main();
