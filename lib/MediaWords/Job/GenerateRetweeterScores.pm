package MediaWords::Job::GenerateRetweeterScores;

#
# Generate retweet polarization scores for media within a topic.
#
# A retweet score is a ratio between -1.0 and 1.0 that compares the numbers of times any story within
# the media is shared by a user who has retweeted one of 2 gropus of users.  So a retweet polarization
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

    $retweeter_group->{ retweeted_useres } = $users;

    return $retweeter_group;
}

# run the sql query to generate the retweeters table for the users in group_a and group_b for the given
# retweeter_score.
#
# that query will add one row to retweeters for each user who retweeted each of the
# users in each of the groups.  so calling this with 'hillaryclinton' in one group and 'realdonaltrump'
# in another group will generate one row for each user who retweeted hillaryclinton at least once and
# one row for each user who retweeted realdonaltrump at least once.
sub _genrerate_retweeters($$$$)
{
    my ( $db, $score, $group_a, $group_b ) = @_;

    my $all_users_lookup = {};
    map { $all_users_lookup->{ $_ } = 1 } ( @{ $group_a->{ retweeted_users } }, @{ $group_b->{ retweeted_users } } );

    my $all_users = [ keys( %{ $all_users_lookup } ) ];

    $db->query( "create temporary table retweeted_users ( user text )" );
    map { $db->query( "insert into retweeted_users values ( ? )", $_ ) } @{ $all_users };

    $db->query( <<SQL, $score->{ retweeter_scores_id } );
insert into retweeters ( retweeter_scores_id, twitter_user, retweeted_user )
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

    $db->query( <<SQL, $score, $score->{ retweeter_scores_id } );
with media_counts as (
    select
            s.media_id,
            sum( rst_a.share_count ) group_a_count,
            sum( rst_b.share_count ) group_b_count
        from
            retweeter_scores rs
            join retweeter_groups rg_a on ( rs.group_a_id = rg_a.retweeter_groups_id )
            join retweeter_stories rst_a on (

insert into retweeter_media ( retweeter_scores_id, media_id, group_a_count, group_b_count, group_a_count_b, score )
    select
            rs.retweeter_scores_id,
            s.media_id,
            sum( a.share_count ) group_a_count,
            sum( b.share_count ) group_b_count,
            ( sum( a.share_count ) * ( sum( b.share_count )::float / ( sum( a.share_count )  + 1 ) ) group_a_count_n,


SQL

}

# run the queries necessary to mine thet tweets and stories for the polarization scores
sub _generated_retweeter_scores($$$$$)
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
