#!/usr/bin/perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Readonly;

# create a media source from a feed url
sub main
{
    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );


    Readonly my $aggregate_stats => " max(similarity) as max_similarity, avg(similarity) as avg_similarity, " .
          "   min(similarity) as min_similarity,  avg(length(extracted_text)) as avg_extracted_length," .
          "   avg(length(html_strip(title || description))) as avg_rss_length,  " .
          "   avg(length(html_strip(description))) as avg_rss_discription ";

    Readonly my $story_restrictions => "publish_date > now() - interval '1 week' and media_id in (select media_id from media_feed_counts where feed_count <= 2)";

    Readonly my $story_extracted_text => "select stories_id,  array_to_string(array_agg(download_text), ' ') as extracted_text   " .
"from (select * from downloads natural join stories natural join download_texts where $story_restrictions  order by downloads_id) "
          . "            as downloads group by stories_id ";

    my $res =
      $db->query( "select * from media natural join  " .
          "(select media_id, $aggregate_stats, count(*) from " .
          "     (select *, similarity(extracted_text, html_strip(title || description) ) " .
          "       from stories, ( $story_extracted_text ) as story_extracted_texts " .
	  " where stories.stories_id = story_extracted_texts.stories_id and $story_restrictions ) as media_extraction_text_similarity group by media_id order by media_id ) as foo"
		);

    my $arrays = $res->arrays;

    print "Output:\n";
    print join "\n" , @{[map { join ", ", @{$_} } @$arrays]};
    print "\n";
}

main();

