use strict;
use warnings;

# parallell ok

use Test::Strict;
use Test::NoWarnings;

$Test::Strict::TEST_WARNINGS = 1;
$Test::Strict::TEST_SKIP     = [
    'lib/MediaWords/CommonLibs.pm',               't/data/cluster_test_1_media_clusters.pl',
    't/data/cluster_test_1_nodes.pl',             't/data/test_feed_download_stories.pl',
    't/data/crawler_stories/gv/1.pl',             't/data/crawler_stories/gv/2.pl',
    't/data/crawler_stories/gv/3.pl',             't/data/crawler_stories/gv/4.pl',
    't/data/crawler_stories/gv/5.pl',             't/data/crawler_stories/gv/6.pl',
    't/data/crawler_stories/gv/7.pl',             't/data/crawler_stories/gv/8.pl',
    't/data/crawler_stories/gv/9.pl',             't/data/crawler_stories/gv/10.pl',
    't/data/crawler_stories/gv/11.pl',            't/data/crawler_stories/gv/12.pl',
    't/data/crawler_stories/gv/13.pl',            't/data/crawler_stories/gv/14.pl',
    't/data/crawler_stories/gv/15.pl',            't/data/crawler_stories/gv/16.pl',
    't/data/crawler_stories/inline_content/1.pl', 't/data/crawler_stories/inline_content/2.pl',
    't/data/crawler_stories/inline_content/3.pl', 't/data/crawler_stories/inline_content/4.pl',
];

all_perl_files_ok( 'script' );
