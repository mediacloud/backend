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
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use TableCreationUtils;

sub main
{

    my $dbh = MediaWords::DB::connect_to_db()
      || die DBIx::Simple::MediaWords->error;

    my ( $tag_sets_id ) = $dbh->query( "select tag_sets_id from tag_sets where name = 'NYTTopics'" )->flat;

    if ( !$tag_sets_id )
    {
        die( "Can't find NYtTopics tag set" );
    }

    $dbh->query( "DROP TABLE if exists media_tag_counts_new" ) or die $dbh->error;

    print "creating table ...\n";
    $dbh->query(
        "create table media_tag_counts_new as " .
          "select count(*) as tag_count, stm.tags_id as tags_id, f.media_id as media_id, t.tag_sets_id " .
          "from stories_tags_map stm, feeds_stories_map fsm, feeds f, stories s, tags t " .
          "where stm.stories_id = fsm.stories_id and fsm.feeds_id = f.feeds_id " .
          "and s.stories_id = fsm.stories_id and s.publish_date > now() - interval '90 days' " .
          "and t.tags_id = stm.tags_id and not (t.tags_id in (??)) " .
          "group by f.media_id, t.tag_sets_id, stm.tags_id order by media_id, t.tag_sets_id, tag_count desc ",
        TableCreationUtils::get_universally_black_listed_tags_ids()
    );

    print "creating indices ...\n";
    my $now = time();
    $dbh->query( "create index media_tag_counts_count_$now on media_tag_counts_new(tag_count)" );
    $dbh->query( "create index media_tag_counts_tag_$now on media_tag_counts_new(tags_id)" );
    $dbh->query( "create index media_tag_counts_media_$now on media_tag_counts_new(media_id)" );
    $dbh->query( "create index media_tag_counts_tag_sets_$now on media_tag_counts_new(tag_sets_id)" );
    $dbh->query( "create unique index media_tag_counts_media_and_tag_$now on media_tag_counts_new(media_id, tags_id)" );
    $dbh->query( "create index media_tag_counts_media_and_tag_sets_$now on media_tag_counts_new(media_id, tag_sets_id)" );

    print "replacing table ...\n";

    $dbh->query( "DROP VIEW if exists media_black_listed_tags" );
    eval { $dbh->query( "drop table if exists media_tag_counts" ) };
    $dbh->query( "alter table media_tag_counts_new rename to media_tag_counts" );

    my $create_view_statement = <<'SQL';
CREATE VIEW media_black_listed_tags as select media.media_id, tags.* from tags, media, media_tag_counts where (media.name ilike '%' || (regexp_replace(tag, '^the ', '')) || '%') and media_tag_counts.media_id=media.media_id and media_tag_counts.tags_id=tags.tags_id;
SQL

    $dbh->query( $create_view_statement );

    $dbh->query( "analyze media_tag_counts" );
}

main();
