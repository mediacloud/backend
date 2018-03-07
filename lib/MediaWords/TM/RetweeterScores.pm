package MediaWords::TM::RetweeterScores;

#
# Generate retweet polarization scores for media within a topic.
#
# A retweet score is a ratio between -1.0 and 1.0 that compares the numbers of times any story within
# the media is shared by a user who has retweeted one of 2 groups of users.  So a retweet polarization
# score for the us presidential election twitter topic might measure the ratio for each media source of
# story shares by clinton vs. trump retweeters.

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

# default number of partitions to divide retweeter scores into
Readonly my $NUM_PARTITIONS => 5;

# tag used to identify and filter out social media platforms from retweeter results
Readonly my $PLATFORM_TAG => 'platforms:all';

# only media with a group_a_count + group_b_count greater than this num will be included in the matrix
Readonly my $MIN_MATRIX_COUNT => 10;

# get the tags_id of the tag that identies social media platforms; if the tag does not exist return -1
sub _get_platform_tags_id($)
{
    my ( $db ) = @_;

    my $tag = MediaWords::Util::Tags::lookup_tag( $db, $PLATFORM_TAG );

    return $tag ? $tag->{ tags_id } : -1;
}

# generate retweeter_groups and retweeter_groups_users_map entries for the given scores and groups.  return
# the resulting retweeter_groups row with the list of retweeted_users attached as a field
sub _generate_retweeter_group($$$)
{
    my ( $db, $score, $users ) = @_;

    my $name = join( ' / ', sort { $a cmp $b } @{ $users } );

    my $retweeter_group = $db->create(
        'retweeter_groups',
        {
            retweeter_scores_id => $score->{ retweeter_scores_id },
            name                => $name
        }
    );

    for my $user ( @{ $users } )
    {
        $db->query( <<SQL, $score->{ retweeter_scores_id }, $retweeter_group->{ retweeter_groups_id }, $user );
insert into retweeter_groups_users_map ( retweeter_scores_id, retweeter_groups_id, retweeted_user )
    values ( ?, ?, ? )
SQL
    }

    $retweeter_group->{ retweeted_users } = $users;

    return $retweeter_group;
}

# run the sql query to generate the retweeters table for the users in group_a and group_b for the given
# retweeter_score.
#
# that query will add one row to retweeters for each user who retweeted each of the
# users in each of the groups.  so calling this with 'hillaryclinton' in one group and 'realdonaltrump'
# in another group will generate one row for each user who retweeted hillaryclinton at least once and
# one row for each user who retweeted realdonaltrump at least once.
sub _generate_retweeters($$$$)
{
    my ( $db, $score, $group_a, $group_b ) = @_;

    my $all_users_lookup = {};
    map { $all_users_lookup->{ $_ } = 1 } ( @{ $group_a->{ retweeted_users } }, @{ $group_b->{ retweeted_users } } );

    my $all_users = [ keys( %{ $all_users_lookup } ) ];

    $db->query( "create temporary table ru ( u text )" );
    map { $db->query( "insert into ru values ( ? )", $_ ) } @{ $all_users };

    $db->query( <<SQL, $score->{ retweeter_scores_id } );
insert into retweeters ( retweeter_scores_id, twitter_user, retweeted_user )
    select distinct
            rs.retweeter_scores_id,
            tt.twitter_user,
            lower( tt.data->'tweet'->'retweeted_status'->'user'->>'screen_name' )
        from topic_tweets tt
            join topic_tweet_days ttd using ( topic_tweet_days_id )
            join retweeter_scores rs using ( topics_id )
        where
            rs.retweeter_scores_id = ? and
            lower( tt.data->'tweet'->'retweeted_status'->'user'->>'screen_name' ) in ( select lower( u ) from ru )
SQL
}

# run the sql query to generate the retweeter_stories table for the given retweeter_score.
#
# that sql query will generate for each story in the topic a count of the numer of times that story was tweeted
# by a retweeter of each retweeted_user in any of the retweeter_groups.  assumes retweeters has already been generated
# for this retweeter_score.
sub _generate_retweeter_stories($$)
{
    my ( $db, $score ) = @_;

    my $platform_tags_id = _get_platform_tags_id( $db );

    $db->query( <<SQL, $score->{ retweeter_scores_id }, $platform_tags_id );
insert into retweeter_stories ( retweeter_scores_id, stories_id, retweeted_user, share_count )
    select
            rs.retweeter_scores_id,
            ttfu.stories_id,
            r.retweeted_user,
            count(*) share_count
        from retweeter_scores rs
            join topic_tweet_full_urls ttfu using ( topics_id )
            join retweeters r
                on ( rs.retweeter_scores_id = r.retweeter_scores_id and r.twitter_user = ttfu.twitter_user )
            join stories s using ( stories_id )
            left join media_tags_map mtm on
                ( mtm.media_id = s.media_id and mtm.tags_id = \$2 )
        where
            rs.retweeter_scores_id = \$1 and
            ttfu.stories_id is not null and
            mtm.tags_id is null -- eliminate platform stories
        group by rs.retweeter_scores_id, ttfu.stories_id, r.retweeted_user
SQL

}

# run the sql query to generate the retweeter_media table for the given retweeter_score.
#
# that query will aggregate the retweeter_stories counts into retwitter_media by summing the share_counts in
# retwitter_stories by media source and by retweeter_groups.  assumes retwitter_stories and retwitter_groups for the
# score have already been generated.
sub _generate_retweeter_media($$)
{
    my ( $db, $score ) = @_;

    $db->query( <<SQL, $score->{ retweeter_scores_id } );
insert into retweeter_media
    ( retweeter_scores_id, media_id, group_a_count, group_b_count, group_a_count_n, score, partition )

    with all_retweeter_stories as (
        select distinct stories_id, retweeter_scores_id from retweeter_stories where retweeter_scores_id = ?
    ),

    mca as (
        select
                ars.retweeter_scores_id,
                s.media_id,
                sum( rst.share_count ) group_count
            from
                all_retweeter_stories ars
                join retweeter_scores rs using ( retweeter_scores_id )
                join stories s using ( stories_id )
                join retweeter_stories rst using ( stories_id, retweeter_scores_id )
                join retweeter_groups rg
                    on ( rg.retweeter_groups_id = rs.group_a_id )
                join retweeter_groups_users_map rgum
                    on ( rgum.retweeter_groups_id = rg.retweeter_groups_id and
                        rst.retweeted_user = rgum.retweeted_user )
            group by ars.retweeter_scores_id, s.media_id
    ),

    mcb as (
        select
                ars.retweeter_scores_id,
                s.media_id,
                sum( rst.share_count ) group_count
            from
                all_retweeter_stories ars
                join retweeter_scores rs using ( retweeter_scores_id )
                join stories s using ( stories_id )
                join retweeter_stories rst using ( stories_id, retweeter_scores_id )
                join retweeter_groups rg
                    on ( rg.retweeter_groups_id = rs.group_b_id )
                join retweeter_groups_users_map rgum
                    on ( rgum.retweeter_groups_id = rg.retweeter_groups_id and
                        rst.retweeted_user = rgum.retweeted_user )
            group by ars.retweeter_scores_id, s.media_id
    ),

    mc as (
        select
                coalesce( mca.retweeter_scores_id, mcb.retweeter_scores_id ) retweeter_scores_id,
                coalesce( mca.media_id, mcb.media_id ) media_id,
                coalesce( mca.group_count, 0 ) group_a_count,
                coalesce( mcb.group_count, 0 ) group_b_count
            from mca
                full join mcb using ( media_id )
    ),

    mc_total as (
        select sum( group_a_count ) group_a_total, sum( group_b_count ) group_b_total from mc
    ),

    mc_norm as (
        select
                mc.media_id,
                case
                    when mc_total.group_a_total = 0 then 0
                    else mc.group_a_count * ( mc_total.group_b_total::float / mc_total.group_a_total )
                end group_a_count_n
            from mc
                cross join mc_total
    ),

    mc_scores as (
        select
                retweeter_scores_id,
                media_id,
                group_a_count,
                group_b_count,
                group_a_count_n,
                case
                    when group_a_count_n::float + group_b_count::float = 0 then 0
                    else
                        1 - ( ( ( group_a_count_n::float /
                                  ( group_a_count_n::float + group_b_count::float ) ) - 0 ) * 2 )
                    end score
            from mc
                join mc_norm using ( media_id )
    )

    select
            mc.*,
            floor( ( 1 + score ) * ( ( num_partitions::float / 2 ) - 0.01 ) ) + 1 as partition
        from mc_scores mc
            join retweeter_scores using ( retweeter_scores_id )
SQL

}

sub _generate_retweeter_partition_matrix($$)
{
    my ( $db, $score ) = @_;

    $db->query( <<SQL, $score->{ retweeter_scores_id } );
insert into retweeter_partition_matrix
    ( retweeter_scores_id, share_count, group_proportion, partition, retweeter_groups_id, group_name )
    with rpm as (
        select
                rs.retweeter_scores_id,
                sum( rs.share_count ) share_count,
                rm.partition,
                rg.retweeter_groups_id,
                rg.name group_name
            from retweeter_stories rs
                join retweeter_groups_users_map rgum
                    on ( rgum.retweeted_user = rs.retweeted_user and
                            rs.retweeter_scores_id = rgum.retweeter_scores_id )
                join retweeter_groups rg using ( retweeter_groups_id )
                join stories s using ( stories_id )
                join retweeter_media rm
                    on ( s.media_id = rm.media_id and rm.retweeter_scores_id = rs.retweeter_scores_id )
            where
                rs.retweeter_scores_id = ? and
                ( rm.group_a_count + rm.group_b_count ) > $MIN_MATRIX_COUNT
            group by rs.retweeter_scores_id, rg.retweeter_groups_id, rm.partition
    ),

    rpm_totals as (
        select
                sum( share_count ) group_share_count,
                retweeter_groups_id
            from rpm
            group by retweeter_groups_id
    )

    select
            rpm.retweeter_scores_id,
            rpm.share_count,
            ( rpm.share_count::float / rpm_totals.group_share_count::float )::float group_proprtion,
            rpm.partition,
            rpm.retweeter_groups_id,
            rpm.group_name
        from rpm
            join rpm_totals using ( retweeter_groups_id );
SQL
}

# Generate retweet polarization scores for the media in the given topic based on the given two sets of
# rewteeted users.  The results of the analysis will be inserted into the the following tables:
# topic_retweeters, topic_retweeter_groups, topic_retweeter_groups_map, topic_retweeter_stories,
# topic_retweeter_poles, topic_retweeter_media
#
# Arguments:
# * topics_id -- twitter topic upon which to base the scores
# * name -- name for this polarization score
# * retweeted_users_a -- list of twitter user handles to use for pole a
# * retweeted_users_b -- list of twitter_user handles to use for pole b
# * num_partitions -- number of partitions by equal score ranges into which to break the media (optional, default = 5)
sub generate_retweeter_scores($$$$$;$)
{
    my ( $db, $topic, $name, $retweeted_users_a, $retweeted_users_b, $num_partitions ) = @_;

    $num_partitions ||= $NUM_PARTITIONS;

    my $score = {
        topics_id      => $topic->{ topics_id },
        name           => $name,
        num_partitions => $num_partitions
    };
    $score = $db->create( 'retweeter_scores', $score );

    $retweeted_users_a = [ map { lc( $_ ) } @{ $retweeted_users_a } ];
    $retweeted_users_b = [ map { lc( $_ ) } @{ $retweeted_users_b } ];

    my $group_a = _generate_retweeter_group( $db, $score, $retweeted_users_a );
    my $group_b = _generate_retweeter_group( $db, $score, $retweeted_users_b );

    my $update = { group_a_id => $group_a->{ retweeter_groups_id }, group_b_id => $group_b->{ retweeter_groups_id } };
    $db->update_by_id( 'retweeter_scores', $score->{ retweeter_scores_id }, $update );

    _generate_retweeters( $db, $score, $group_a, $group_b );

    _generate_retweeter_stories( $db, $score );

    _generate_retweeter_media( $db, $score );

    _generate_retweeter_partition_matrix( $db, $score );

    return $score;
}

# generate csv dump of retweeter_media rows for a given retweeter_score.  include metrics from snap.medium_link_counts
# from the latest overall timespan if one exists.
sub generate_media_csv($$)
{
    my ( $db, $score ) = @_;

    my $timespan = MediaWords::TM::get_latest_overall_timespan( $db, $score->{ topics_id } );

    my $retweeter_scores_id = int( $score->{ retweeter_scores_id } );
    my $timespans_id = $timespan ? int( $timespan->{ timespans_id } ) : -1;

    my $media_csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<SQL );
select
        rm.*,
        m.name media_name,
        m.url media_url,
        ga.name group_a_name,
        gb.name group_b_name,
        mlc.media_inlink_count,
        mlc.story_count,
        mlc.bitly_click_count,
        mlc.simple_tweet_count
    from retweeter_scores rs
        join retweeter_media rm using ( retweeter_scores_id )
        join media m using ( media_id )
        join retweeter_groups ga on ( rs.group_a_id = ga.retweeter_groups_id )
        join retweeter_groups gb on ( rs.group_b_id = gb.retweeter_groups_id )
        left join snap.medium_link_counts mlc on
            ( mlc.timespans_id = $timespans_id and mlc.media_id = rm.media_id )
    where
        rs.retweeter_scores_id = $retweeter_scores_id
SQL

    return $media_csv;
}

# generate csv from retweeter_partition_matrix
sub generate_matrix_csv($$)
{
    my ( $db, $score ) = @_;

    my $matrix_csv = MediaWords::Util::CSV::get_query_as_csv( $db, <<SQL, $score->{ retweeter_scores_id } );
select rpm.* from retweeter_partition_matrix rpm where retweeter_scores_id = ? order by group_name, partition
SQL

    return $matrix_csv;
}

1;
