#!/usr/bin/env perl

# print meta states about a controversy, such as total number of media sources, feeds, and stories queried

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;
use Modern::Perl "2012";

use MediaWords::DB;
use MediaWords::DBI::Queries;

# stats about number of media sources in query
sub print_query_media_counts
{
    my ( $db, $controversies_id ) = @_;

    my ( $total_count ) = $db->query( <<END, $controversies_id )->flat;
select count( distinct msmm.media_id ) media_count
    from controversies c, query_story_searches qss, queries_media_sets_map qmsm, 
        media_sets_media_map msmm
    where c.controversies_id = ? and c.query_story_searches_id = qss.query_story_searches_id and
        qss.queries_id = qmsm.queries_id and qmsm.media_sets_id = msmm.media_sets_id
END

    my $media_counts = $db->query( <<END, $controversies_id )->hashes;
select count(*) media_count, ms.name media_set_name
    from controversies c, query_story_searches qss, queries_media_sets_map qmsm, 
        media_sets_media_map msmm, media_sets ms
    where c.controversies_id = ? and c.query_story_searches_id = qss.query_story_searches_id and
        qss.queries_id = qmsm.queries_id and qmsm.media_sets_id = msmm.media_sets_id and
        msmm.media_sets_id = ms.media_sets_id
    group by ms.media_sets_id, ms.name
    order by ms.name
END

    say "Total Media Sources in Query: $total_count\n";

    say "Media Counts for Each Media Set in Query:";
    for my $media_count ( @{ $media_counts } )
    {
        say "\t$media_count->{ media_set_name }: $media_count->{ media_count }";
    }

    say "\n";
}

# stats about number of feeds in query
sub print_query_feed_counts
{
    my ( $db, $controversies_id ) = @_;

    my ( $total_count ) = $db->query( <<END, $controversies_id )->flat;
select count( distinct f.feeds_id ) feed_count
    from controversies c, query_story_searches qss, queries_media_sets_map qmsm, 
        media_sets_media_map msmm, feeds f
    where c.controversies_id = ? and c.query_story_searches_id = qss.query_story_searches_id and
        qss.queries_id = qmsm.queries_id and qmsm.media_sets_id = msmm.media_sets_id and
        msmm.media_id = f.media_id
END

    my $feed_counts = $db->query( <<END, $controversies_id )->hashes;
select count(*) feed_count, ms.name media_set_name
    from controversies c, query_story_searches qss, queries_media_sets_map qmsm, 
        media_sets_media_map msmm, feeds f, media_sets ms
    where c.controversies_id = ? and c.query_story_searches_id = qss.query_story_searches_id and
        qss.queries_id = qmsm.queries_id and qmsm.media_sets_id = msmm.media_sets_id and
        msmm.media_id = f.media_id and msmm.media_sets_id = ms.media_sets_id
    group by ms.media_sets_id, ms.name
END

    say "Total Feeds in Query: $total_count\n";

    say "Feed Counts for Each Media Set in Query:";
    for my $feed_count ( @{ $feed_counts } )
    {
        say "\t$feed_count->{ media_set_name }: $feed_count->{ feed_count }";
    }

    say "\n";

}

# stats about total stories collected within query
sub print_query_story_counts
{
    my ( $db, $controversies_id ) = @_;

    my ( $total_count ) = $db->query( <<END, $controversies_id )->flat;
select count( distinct fsm.stories_id ) story_count
    from controversies c, query_story_searches qss, queries_media_sets_map qmsm, 
        media_sets_media_map msmm, feeds f, feeds_stories_map fsm
    where c.controversies_id = ? and c.query_story_searches_id = qss.query_story_searches_id and
        qss.queries_id = qmsm.queries_id and qmsm.media_sets_id = msmm.media_sets_id and
        msmm.media_id = f.media_id and f.feeds_id = fsm.feeds_id
END

    my $story_counts = $db->query( <<END, $controversies_id )->hashes;
select count(*) story_count, ms.name media_set_name
    from controversies c, query_story_searches qss, queries_media_sets_map qmsm, 
        media_sets_media_map msmm, feeds f, media_sets ms, feeds_stories_map fsm
    where c.controversies_id = ? and c.query_story_searches_id = qss.query_story_searches_id and
        qss.queries_id = qmsm.queries_id and qmsm.media_sets_id = msmm.media_sets_id and
        msmm.media_id = f.media_id and msmm.media_sets_id = ms.media_sets_id and
        f.feeds_id = fsm.stories_id
    group by ms.media_sets_id, ms.name
END

    say "Total Stories in Query: $total_count\n";

    say "Story Counts for Each Media Set in Query:";
    for my $story_count ( @{ $story_counts } )
    {
        say "\t$story_count->{ media_set_name }: $story_count->{ story_count }";
    }

    say "";

}

# description of the query
sub print_query_info
{
    my ( $db, $controversies_id ) = @_;

    my $query_story_search = $db->query( <<END, $controversies_id )->hash;
select qss.* from query_story_searches qss, controversies c
    where qss.query_story_searches_id = c.query_story_searches_id and c.controversies_id = ?
END

    say "Search Pattern: [ $query_story_search->{ pattern } ]\n";

    my $query = MediaWords::DBI::Queries::find_query_by_id( $db, $query_story_search->{ queries_id } );

    say MediaWords::DBI::Queries::get_full_description( $query );

}

# print stats about the overall query that the query_story_search was run on
sub print_query_stats
{
    my ( $db, $controversies_id ) = @_;

    say <<END;
Query Stats

The following info describes the query used to run the search for seed stories within the Media Cloud database.

The numbers of media sources, feeds, and stories are the total number of stories searched.  The seed stories consist
of the subset of those media sources, feeds, and stories found to match the search pattern.
END

    print_query_info( $db, $controversies_id );

    print_query_media_counts( $db, $controversies_id );

    print_query_feed_counts( $db, $controversies_id );

    # print_query_story_counts( $db, $controversies_id );
}

# print stats about number of media within the controversy
sub print_controversy_media
{
    my ( $db, $controversies_id ) = @_;

    my ( $total_count ) = $db->query( <<END, $controversies_id )->flat;
select count( distinct s.media_id ) media_count from controversy_stories cs, stories s
    where cs.controversies_id = ? and cs.stories_id = s.stories_id
END
    say "Total Media in Controversy: $total_count\n";

    my ( $spider_count ) = $db->query( <<END, $controversies_id )->flat;
select count( distinct s.media_id ) media_count 
    from controversy_stories cs, stories s, media_tags_map mtm, tags t, tag_sets ts
    where cs.controversies_id = ? and cs.stories_id = s.stories_id and s.media_id = mtm.media_id and 
        mtm.tags_id = t.tags_id and t.tag_sets_id = ts.tag_sets_id and
        t.tag = 'spidered' and ts.name = 'spidered'
END

    say "Total Spidered Media in Controversy: $spider_count\n";
}

# print stats about number of stories within the controversy
sub print_controversy_stories
{
    my ( $db, $controversies_id ) = @_;

    my ( $total_count ) = $db->query( <<END, $controversies_id )->flat;
select count( distinct s.stories_id ) media_count from controversy_stories cs, stories s
    where cs.controversies_id = ? and cs.stories_id = s.stories_id
END
    say "Total Stories in Controversy: $total_count\n";

    my ( $spider_count ) = $db->query( <<END, $controversies_id )->flat;
select count( distinct cs.stories_id ) media_count 
    from controversy_stories cs, stories_tags_map stm, tags t, tag_sets ts
    where cs.controversies_id = ? and cs.stories_id = stm.stories_id and 
        stm.tags_id = t.tags_id and t.tag_sets_id = ts.tag_sets_id and
        t.tag = 'spidered' and ts.name = 'spidered'
END

    say "Total Spidered Stories in Controversy: $spider_count\n";

    my $media_set_counts = $db->query( <<END, $controversies_id )->hashes;
select distinct count( * ) story_count, ms.name media_set_name
    from controversy_stories cs, stories s, media_sets_media_map msmm, media_sets ms
    where cs.controversies_id = ? and cs.stories_id = s.stories_id and
        s.media_id = msmm.media_id and msmm.media_sets_id = ms.media_sets_id and
        ms.set_type = 'collection'
    group by ms.media_sets_id, ms.name
    order by count(*) desc
END

    say "Stories in Controversy by Media Set:\n";

    for my $media_set_count ( @{ $media_set_counts } )
    {
        say "\t$media_set_count->{ media_set_name }: $media_set_count->{ story_count }";
    }

    say "\n";

    my ( $link_count ) = $db->query( <<END, $controversies_id )->flat;
select count(*) from controversy_links_cross_media where controversies_id = ?
END

    say "Total Cross Media Links in Controversy: $link_count\n";

    my $iteration_counts = $db->query( <<END, $controversies_id )->hashes;
select count(*) iteration_count, iteration from controversy_stories
    where controversies_id = ?
    group by iteration
    order by iteration
END

    say "Story Counts by Iteration:";
    for my $iteration_count ( @{ $iteration_counts } )
    {
        say "\t$iteration_count->{ iteration }: $iteration_count->{ iteration_count }";
    }
    say "";

}

# print stats about the controversy itself
sub print_controversy_stats
{
    my ( $db, $controversies_id ) = @_;

    say <<END;
Controversy Stats

The following info describes the media sources, feed, stories, and links found within the controversy itself.
END

    print_controversy_media( $db, $controversies_id );

    print_controversy_stories( $db, $controversies_id );
}

sub main
{
    my ( $controversies_id );

    Getopt::Long::GetOptions( "controversy=s" => \$controversies_id, ) || return;

    die( "usage: $0 --controversy < controversies_id >" ) unless ( $controversies_id );

    my $db = MediaWords::DB::connect_to_db;

    my $controversy = $db->find_by_id( 'controversies', $controversies_id )
      || die( "Unable to find controversy '$controversies_id'" );

    say "Controversy Stats for $controversy->{ name }\n";

    print_query_stats( $db, $controversies_id );

    print_controversy_stats( $db, $controversies_id );

}

main();
