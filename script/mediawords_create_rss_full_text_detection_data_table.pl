#!/usr/bin/env perl

# create media_tag_counts table by querying the database tags / feeds / stories

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/.";
}

use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use TableCreationUtils;

sub main
{

    my $dbh = MediaWords::DB::connect_to_db()
      || die DBIx::Simple::MediaWords->error;

    $dbh->query( "DROP TABLE if exists media_rss_full_text_detection_data_new" ) or die $dbh->error;

    my $table_creation_query = <<"SQL";
     create table media_rss_full_text_detection_data_new as  
        select * from 
          (select media_id, max(similarity) as max_similarity, 
            avg(similarity) as avg_similarity, min(similarity) as min_similarity,
            avg(length(extracted_text)) as avg_extracted_length, avg(length(html_strip(title || description))) 
            as avg_rss_length, avg(length(html_strip(description))) as avg_rss_discription, count(*) 
             from (select *, similarity(extracted_text, html_strip(title || description) ) from
                 stories, 
                   (select stories_id, array_to_string(array_agg(download_text), ' ') as extracted_text
                      from 
                         (select * from downloads natural join stories natural join download_texts 
                             where publish_date > now() - interval ' 1 week'  order by downloads_id)
                             as downloads group by stories_id) as story_extracted_texts
                         where stories.stories_id = story_extracted_texts.stories_id and
                            publish_date > now() - interval '1 week' ) as media_extraction_text_similarity 
         group by media_id order by media_id ) as foo  ;
SQL

    $dbh->query( $table_creation_query );

    print "creating indices ...\n";
    my $now = time();

    $dbh->query(
        "create index media_rss_full_text_detection_data_media_$now on media_rss_full_text_detection_data_new(media_id)" );

    print "replacing table ...\n";

    eval { $dbh->query( "drop table if exists media_rss_full_text_detection_data" ) };
    $dbh->query( "alter table media_rss_full_text_detection_data_new rename to media_rss_full_text_detection_data" );

    $dbh->query( "analyze media_rss_full_text_detection_data" );
}

main();
