package MediaWords::TM::FetchTopicTweets;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'topics_mine.fetch_topic_tweets' );

1;
