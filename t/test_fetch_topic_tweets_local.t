use strict;
use warnings;

# test MediaWords::Job::FetchTopicTweets

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::Test::TopicTweets;

sub main
{

    MediaWords::Test::TopicTweets::run_tests_on_mock_apis();
}

main();
