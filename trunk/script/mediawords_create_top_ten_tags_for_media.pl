#!/usr/bin/env perl

# create daily_feed_tag_counts table by querying the database tags / feeds / stories

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use DBI;
use DBIx::Simple::MediaWords;
use DBIx::Simple;

sub main
{

    #grabs the top tags for the media id  and tag set
    # Using a subselect for performance reason. psql should be smart enough to optimize a join but it isn't

    #NOTE Postgresql only allows us to sort by a single column since there is an EXCEPT clause :(
    my $top_ten_for_media_id_query = <<'SQL';
select * from tags natural join ( 

select media.name, foo1.* from tags, media, 
(select  media_tag_counts.media_id, media_tag_counts.tags_id, tag_count as media_tag_count, media_tag_counts.tag_sets_id from media_tag_counts where media_tag_counts.media_id=? and media_tag_counts.tag_sets_id=? group by  media_tag_counts.media_id, media_tag_counts.tag_sets_id, media_tag_counts.tags_id, media_tag_count order by media_tag_counts.media_id, media_tag_count desc limit 1000 ) as foo1 
 where foo1.tags_id=tags.tags_id and foo1.media_id=media.media_id  

 EXCEPT select bar.* from (select media.name, foo2.* from tags, media, 
(select  media_tag_counts.media_id, media_tag_counts.tags_id, tag_count as media_tag_count, media_tag_counts.tag_sets_id from media_tag_counts where media_tag_counts.media_id=? and media_tag_counts.tag_sets_id=? group by  media_tag_counts.media_id, media_tag_counts.tag_sets_id, media_tag_counts.tags_id, media_tag_count order by media_tag_counts.media_id, media_tag_count desc limit 1000) as foo2 
 where foo2.tags_id=tags.tags_id and foo2.media_id=media.media_id )
as bar natural join media_black_listed_tags) as top_ten_non_black_listed 
 order by media_tag_count desc limit 10;

SQL

    my $table_name      = "top_ten_tags_for_media";
    my $temp_table_name = $table_name . time();

    #my $dbh = DBI->connect( MediaWords::DB::connect_info );

    #    print "restarting sequence ...\n";
    #    $dbh->do("alter sequence top_ten_tags_for_media_seq restart 1");

    my $db = MediaWords::DB::connect_to_db();

    #evil hack
    $db->query( "DROP TABLE if exists $temp_table_name" );
    $db->query(
"CREATE TABLE $temp_table_name (  media_id integer not null references media on delete cascade, tags_id integer not null references tags,     media_tag_count integer not null,     tag_name character varying(512) not null,     tag_sets_id integer not null references tag_sets) "
    );

    #	$db->query("TRUNCATE TABLE $temp_table_name");

    my @media_ids = $db->query( "select media_id from media order by media_id" )->flat;

    my @tag_set_ids = $db->query( " select distinct(tag_sets_id) from media_tag_counts order by tag_sets_id" )->flat;
    my @rows_to_insert;

    my $i = 0;
    foreach my $media_id ( sort { $a <=> $b } @media_ids )
    {
        $i++;
        print "media_id: $media_id  ($i of " . @media_ids . ") \n";

        foreach my $tag_set_id ( sort { $a <=> $b } @tag_set_ids )
        {

            #print "Executing query:'$top_ten_for_media_id_query'\n";

            my $result = $db->query( $top_ten_for_media_id_query, $media_id, $tag_set_id, $media_id, $tag_set_id );

            foreach my $row ( $result->hashes() )
            {
                push( @rows_to_insert, $row );
            }
        }
    }

    $i = 0;
    foreach my $row_to_insert ( @rows_to_insert )
    {
        $i++;
        print "inserting row $i of  " . @rows_to_insert . "\n";

        my @value = %{ $row_to_insert };

        #print join ' ,' , @value;
        #print "\n";

        $db->query(
            " insert into $temp_table_name (media_id, tags_id, media_tag_count, tag_name, tag_sets_id) VALUES (??)",
            $row_to_insert->{ media_id },
            $row_to_insert->{ tags_id },
            $row_to_insert->{ media_tag_count },
            $row_to_insert->{ tag },
            $row_to_insert->{ tag_sets_id }
        );
    }

    print "creating indices ...\n";

    #	print "create index media_id_index on $temp_table_name (media_id)\n";

    $db->query_only_warn_on_error( "drop index if exists media_id_index" );
    $db->query_only_warn_on_error( "drop index if exists tag_sets_id_index" );
    $db->query_only_warn_on_error( "drop index if exists media_id_and_tag_sets_id_index" );

    $db->query_only_warn_on_error( "create index media_id_index on $temp_table_name (media_id)" );
    $db->query_only_warn_on_error( "create index tag_sets_id_index on $temp_table_name (tag_sets_id)" );
    $db->query_only_warn_on_error(
        "create index media_id_and_tag_sets_id_index on $temp_table_name (media_id,tag_sets_id)" );

#    print "creating foreign keys ...\n";
#    $dbh->do("alter table only top_ten_tags_for_media_new add constraint tag foreign key (tags_id) references tags on delete cascade");
#    $dbh->do(" alter table only top_ten_tags_for_media_new add constraint media foreign key (media_id) references media on delete cascade");

    print "replacing table ...\n";
    $db->query( "drop table if exists $table_name" );
    $db->query( "alter table $temp_table_name rename to $table_name" );

    $db->query( "analyze $table_name" );
}

main();
