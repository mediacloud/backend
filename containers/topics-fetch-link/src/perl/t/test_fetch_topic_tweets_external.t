use strict;
use warnings;

use Modern::Perl '2015';
use MediaWords::CommonLibs;

use MediaWords::Test::TopicTweets;

sub main
{
    MediaWords::Test::TopicTweets::run_tests_on_external_apis();
}

main();
