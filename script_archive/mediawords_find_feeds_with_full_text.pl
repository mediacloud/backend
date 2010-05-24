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

# create a media source from a feed url
sub main
{
    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    my $res =
      $db->query( "select * from media natural join  " .
          "(select media_id, max(similarity) as max_similarity, avg(similarity) as avg_similarity, " .
          "   min(similarity) as min_similarity,  avg(length(extracted_text)) as avg_extracted_length," .
          "   avg(length(html_strip(title || description))) as avg_rss_length,  " .
          "   avg(length(html_strip(description))) as avg_rss_discription, count(*) from "
          "     (select *, similarity(extracted_text, html_strip(title || description) ) " .
          "       from stories, (select stories_id,  array_to_string(array_agg(download_text), ' ') as extracted_text   " .
"from (select * from downloads natural join stories natural join download_texts where publish_date > now() - interval ' 1 week'  order by downloads_id) "
          . "            as downloads group by stories_id) as story_extracted_texts where stories.stories_id = story_extracted_texts.stories_id and publish_date > now() - interval '1 week' ) as media_extraction_text_similarity group by media_id order by media_id ) as foo"
      );

    print "Output:\n";
    print $res->flat;
    print "\n";
}

main();
