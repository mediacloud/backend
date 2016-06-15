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
     with active_media as (
         select media_id from media_health where num_stories_90 > 10 and is_healthy and has_active_feed
     ),

     story_texts as (
         select
                d.stories_id,
                min( dt.download_text ) as story_text
            from downloads d
                join download_texts dt on ( d.downloads_id = dt.downloads_id )
            where
                d.feeds_id in (
                    select feeds_id from feeds where media_id in ( select media_id from active_media )
                ) and
                date_trunc( 'day'::text, ss.publish_date ) between now() - '1 day'::interval and now()
            group by ss.stories_id
     ),

     story_similarities as (
         select
                s.stories_id,
                s.media_id,
                s.publish_date,
                similarity( st.story_text, s.description ) text_similarity,
                length( story_text ) text_length,
                length( description ) description_length
            from stories s
                join active_media am on ( s.media_id = am.media_id )
                join story_texts st on ( s.stories_id = st.stories_id )
            where
                date_trunc( 'day'::text, s.publish_date ) between now() - '1 day'::interval and now()
    )

    select
            media_id,
            max( text_similarity ) as max_similarity,
            min( text_similarity ) as min_similarity,
            avg( text_similarity ) as avg_similarity,
            avg( text_length ) as avg_text_length,
            avg( description_length ) as avg_description_length,
            count(*) as num_stories,
            min( publish_date ) as publish_date
        from
            story_similarities ss
        group by ss.media_id
        order by ss.media_id
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
