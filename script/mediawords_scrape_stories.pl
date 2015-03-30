#!/usr/bin/env perl

# generate media_health table, which contains denormalized results of analytical queries run on
# the media_stats table to enable quick analysis of the health of individual media sources.
#
# also generate a report that includes a summary of overall system health as well as alerts
# for specific media that appear unhealthy

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use CHI;
use Data::Dumper;
use Encode;
use Getopt::Long;
use HTML::LinkExtractor;
use List::MoreUtils;
use URI::Split;

use MediaWords::CM::GuessDate;
use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::ScrapeStories;
use MediaWords::Util::Config;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;

sub main
{
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    my $p = {};

    Getopt::Long::GetOptions(
        $p,           "start_url=s",  "story_url_pattern=s", "page_url_pattern=s",
        "media_id=i", "start_date=s", "end_date=s",          "max_pages=i",
        "debug!",     "dry_run!"
    ) || return;

    if ( !( $p->{ start_url } && $p->{ story_url_pattern } && $p->{ page_url_pattern } && $p->{ media_id } ) )
    {
        die( <<END );
usage: $0 --start_url <url> --story_url_pattern <regex> --page_url_pattern <regex> --media_id <id> [ --start_date <date> --end_date <date> --max_pages <num> ]
END
    }

    $p->{ db } = MediaWords::DB::connect_to_db;

    my $ss = MediaWords::ScrapeStories->new( $p )->scrape_stories();
}

main();
