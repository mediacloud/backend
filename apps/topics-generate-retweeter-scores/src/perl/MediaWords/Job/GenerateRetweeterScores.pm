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
# ./script/run_in_env.sh mjm_worker.pl lib/MediaWords/Job/GenerateRetweetScores.pm
#

use strict;
use warnings;

use Moose;
with 'MediaWords::JobManager::AbstractStatefulJob';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::TM::RetweeterScores;

use Readonly;

sub use_job_state()
{
    return 1;
}

sub get_state_table_info
{
    return { table => 'retweeter_scores', state => 'state', message => 'message' };
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
# * match_type -- match by retweeted user or by regex in tweet content (optional, default=retweet)
sub run($;$)
{
    my ( $self, $args ) = @_;

    my $db = MediaWords::DB::connect_to_db();

    map { LOGDIE( "$_ required" ) unless ( $args->{ $_ } ) } ( qw/topics_id name retweeted_users_a retweeted_users_b/ );

    my $topic             = $db->require_by_id( 'topics', $args->{ topics_id } );
    my $name              = $args->{ name };
    my $retweeted_users_a = $args->{ retweeted_users_a };
    my $retweeted_users_b = $args->{ retweeted_users_b };
    my $num_partitions    = $args->{ num_partitions };
    my $match_type        = $args->{ match_type };

    map { die( "$_ arg must be a list" ) unless ref( $args->{ $_ } ) eq ref( [] ) }
      ( qw/retweeted_users_a retweeted_users_b/ );

    die( "topic '$topic->{ topics_id }' must be a twitter topic" ) unless ( $topic->{ platform } eq 'twitter' );

    MediaWords::TM::RetweeterScores::generate_retweeter_scores( $db, $topic, $name, $retweeted_users_a, $retweeted_users_b,
        $num_partitions, $match_type );

    return 1;
}

no Moose;    # gets rid of scaffolding

1;
