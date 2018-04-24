package MediaWords::TM::FetchTopicTweets;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.tm.fetch_topic_tweets' );

1;
