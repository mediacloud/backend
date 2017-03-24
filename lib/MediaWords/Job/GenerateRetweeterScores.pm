package MediaWords::Job::GenerateRetweeterScores;

#
# Generate retweet polarization scores for media within a topic.
#
# A retweet score is a ratio between -1.0 and 1.0 that compares the numbers of times any story within
# the media is shared by a user who has retweeted one of 2 groups of users.  So a retweet polarization
# score for the us presidential election twitter topic might measure the ratio for each media source of
# story shares by clinton vs. trump retweeters.
#
# Start this worker script by running:
#
# ./script/run_with_carton.sh local/bin/mjm_worker.pl lib/MediaWords/Job/GenerateRetweetScores.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::AbstractJob';

BEGIN
{
    use FindBin;

    # "lib/" relative to "local/bin/mjm_worker.pl":
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub use_job_state()
{
    return 1;
}

sub get_state_table_info
{
    return { table => 'retweeter_poles', state => 'state', message => 'message' };
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
    select distinct rs.retweeter_scores_id, tt.twitter_user, tt.data->'tweet'->'retweeted_status'->'user'->>'screen_name'
        from topic_tweets tt
            join topic_tweet_days ttd using ( topic_tweet_days_id )
            join retweeter_scores rs using ( topics_id )
        where
            rs.retweeter_scores_id = ? and
            tt.data->'tweet'->'retweeted_status'->'user'->>'screen_name' in ( select u from ru )
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

    $db->query( <<SQL, $score->{ retweeter_scores_id } );
insert into retweeter_stories ( retweeter_scores_id, stories_id, retweeted_user, share_count )
    select
            rs.retweeter_scores_id,
            ttfu.stories_id,
            r.retweeted_user,
            count(*) share_count
        from retweeter_scores rs
            join topic_tweet_full_urls ttfu using ( topics_id )
            join topic_tweets tt using ( topic_tweets_id )
            join retweeters r
                on ( rs.retweeter_scores_id = r.retweeter_scores_id and r.twitter_user = tt.twitter_user )
        where
            rs.retweeter_scores_id = ? and
            ttfu.stories_id is not null
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
insert into retweeter_media ( retweeter_scores_id, media_id, group_a_count, group_b_count, group_a_count_n, score )
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
    )

    select
            retweeter_scores_id,
            media_id,
            group_a_count,
            group_b_count,
            group_a_count_n,
            1 - ( ( ( group_a_count_n::float / ( group_a_count_n::float + group_b_count::float ) ) - 0 ) * 2 )
                score
        from mc
            join mc_norm using ( media_id )
SQL

}

# run the queries necessary to mine thet tweets and stories for the polarization scores
sub _generate_retweeter_scores($$$$$)
{
    my ( $db, $topic, $name, $retweeted_users_a, $retweeted_users_b ) = @_;

    my $score = $db->create( 'retweeter_scores', { topics_id => $topic->{ topics_id }, name => $name } );

    my $group_a = _generate_retweeter_group( $db, $score, $retweeted_users_a );
    my $group_b = _generate_retweeter_group( $db, $score, $retweeted_users_b );

    my $update = { group_a_id => $group_a->{ retweeter_groups_id }, group_b_id => $group_b->{ retweeter_groups_id } };
    $db->update_by_id( 'retweeter_scores', $score->{ retweeter_scores_id }, $update );

    _generate_retweeters( $db, $score, $group_a, $group_b );

    _generate_retweeter_stories( $db, $score );

    _generate_retweeter_media( $db, $score );
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
sub run_statefully($$;$)
{
    my ( $self, $db, $args ) = @_;

    map { LOGDIE( "$_ required" ) unless ( $args->{ $_ } ) } ( qw/topics_id name retweeted_users retweeted_users_b/ );

    my $topic             = $db->require_by_id( 'topics', $args->{ topics_id } );
    my $name              = $args->{ name };
    my $retweeted_users_a = $args->{ retweeted_users_a };
    my $retweeted_users_b = $args->{ retweeted_users_b };

    map { die( "$_ arg must be a list" ) unless ref( $_ ) eq ref( [] ) } ( qw/retweeted_users_a retweeted_users_b/ );

    _generate_retweeter_scores( $db, $topic, $name, $retweeted_users_a, $retweeted_users_b );

    return 1;
}

no Moose;    # gets rid of scaffolding

# Return package name instead of 1 or otherwise worker.pl won't know the name of the package it's loading
__PACKAGE__;
