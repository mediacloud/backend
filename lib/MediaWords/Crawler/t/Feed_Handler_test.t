#!/usr/bin/perl

# test MediaWords::Crawler::FeedHandler against manually extracted downloads

use strict;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Crawler::FeedHandler;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More;
use HTML::CruftText 0.02;
use Test::Deep;

use MediaWords::DB;

sub convert_to_local_time_zone
{
    my ( $db, $sql_date ) = @_;

    my ( $local_sql_date ) = $db->query( "select ( ?::timestamptz )::timestamp", $sql_date )->flat;

    return $local_sql_date;
}

sub main
{
    my $db = MediaWords::DB::connect_to_db || die( "can't connect to db" );

    my $test_cases = [
        {
            test_name    => 'standard_single_item',
            media_id     => 1,
            publish_date => convert_to_local_time_zone( $db, '2012-01-09 06:20:10-0' ),
            feed_input   => <<'__END_TEST_CASE__',
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
	xmlns:content="http://purl.org/rss/1.0/modules/content/"
	xmlns:wfw="http://wellformedweb.org/CommentAPI/"
	xmlns:dc="http://purl.org/dc/elements/1.1/"
	xmlns:atom="http://www.w3.org/2005/Atom"
	xmlns:sy="http://purl.org/rss/1.0/modules/syndication/"
	xmlns:slash="http://purl.org/rss/1.0/modules/slash/"
	xmlns:creativeCommons="http://backend.userland.com/creativeCommonsRssModule"
>

<channel>
	<title>David Larochelle&#039;s Blog</title>
	<atom:link href="http://blogs.law.harvard.edu/dlarochelle/feed/" rel="self" type="application/rss+xml" />
	<link>https://blogs.law.harvard.edu/dlarochelle</link>
	<description></description>
	<lastBuildDate>Mon, 09 Jan 2012 06:20:10 +0000</lastBuildDate>

	<language>en</language>
	<sy:updatePeriod>hourly</sy:updatePeriod>
	<sy:updateFrequency>1</sy:updateFrequency>
	<generator>http://wordpress.org/?v=3.2.1</generator>
<creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>
		<item>
		<title>Why Life is Too Short for Spiral Notebooks</title>

		<link>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/</link>
		<comments>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/#comments</comments>
		<pubDate>Mon, 09 Jan 2012 06:20:10 +0000</pubDate>
		<dc:creator>dlarochelle</dc:creator>
				<category><![CDATA[Uncategorized]]></category>

		<guid isPermaLink="false">http://blogs.law.harvard.edu/dlarochelle/?p=350</guid>

		<description>One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible.</description>
			<content:encoded><p>One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible. This post will detail why I’ve switched to using wireless bound notebooks exclusively.</p></content:encoded>
			<wfw:commentRss>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/feed/</wfw:commentRss>
		<slash:comments>0</slash:comments>
	<creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>
	</item>
        </channel>
</rss>
__END_TEST_CASE__
            ,
            test_output => [
                {
                    'collect_date' => '2012-01-10T20:03:48',
                    'media_id'     => 1,
                    'publish_date' => convert_to_local_time_zone( $db, '2012-01-09 06:20:10-0' ),
                    'url' =>
                      'https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/',
                    'title' => 'Why Life is Too Short for Spiral Notebooks',
                    'guid'  => 'http://blogs.law.harvard.edu/dlarochelle/?p=350',
                    'description' =>
'One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible.'
                }
            ]
        },
        {
            test_name    => 'no title or time',
            media_id     => 1,
            publish_date => convert_to_local_time_zone( $db, '2012-01-09 06:20:10-0' ),
            feed_input   => <<'__END_TEST_CASE__',
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"
	xmlns:content="http://purl.org/rss/1.0/modules/content/"
	xmlns:wfw="http://wellformedweb.org/CommentAPI/"
	xmlns:dc="http://purl.org/dc/elements/1.1/"
	xmlns:atom="http://www.w3.org/2005/Atom"
	xmlns:sy="http://purl.org/rss/1.0/modules/syndication/"
	xmlns:slash="http://purl.org/rss/1.0/modules/slash/"
	xmlns:creativeCommons="http://backend.userland.com/creativeCommonsRssModule"
>

<channel>
	<title>David Larochelle&#039;s Blog</title>
	<atom:link href="http://blogs.law.harvard.edu/dlarochelle/feed/" rel="self" type="application/rss+xml" />
	<link>https://blogs.law.harvard.edu/dlarochelle</link>
	<description></description>
	<lastBuildDate>Mon, 09 Jan 2012 06:20:10 +0000</lastBuildDate>

	<language>en</language>
	<sy:updatePeriod>hourly</sy:updatePeriod>
	<sy:updateFrequency>1</sy:updateFrequency>
	<generator>http://wordpress.org/?v=3.2.1</generator>
<creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>
		<item>
		<title></title>

		<link>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/</link>
		<comments>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/#comments</comments>
		<dc:creator>dlarochelle</dc:creator>
				<category><![CDATA[Uncategorized]]></category>

		<guid isPermaLink="false">http://blogs.law.harvard.edu/dlarochelle/?p=350</guid>

		<description>One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible.</description>
			<content:encoded><p>One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible. This post will detail why I’ve switched to using wireless bound notebooks exclusively.</p></content:encoded>
			<wfw:commentRss>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/feed/</wfw:commentRss>
		<slash:comments>0</slash:comments>
	<creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>
	</item>
        <item>
		<title>Skipped Item</title>

		<comments>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/#comments</comments>
		<dc:creator>dlarochelle</dc:creator>
				<category><![CDATA[Uncategorized]]></category>

		<description>One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible.</description>
			<content:encoded><p>One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible. This post will detail why I’ve switched to using wireless bound notebooks exclusively.</p></content:encoded>
			<wfw:commentRss>https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/feed/</wfw:commentRss>
		<slash:comments>0</slash:comments>
	<creativeCommons:license>http://creativecommons.org/licenses/by-sa/3.0/</creativeCommons:license>
	</item>
        </channel>
</rss>
__END_TEST_CASE__
            ,
            test_output => [
                {
                    'collect_date' => '2012-01-10T20:03:48',
                    'media_id'     => 1,
                    'publish_date' => convert_to_local_time_zone( $db, '2012-01-09 06:20:10-0' ),
                    'url' =>
                      'https://blogs.law.harvard.edu/dlarochelle/2012/01/09/why-life-is-too-short-for-spiral-notebooks/',
                    'title' => '(no title)',
                    'guid'  => 'http://blogs.law.harvard.edu/dlarochelle/?p=350',
                    'description' =>
'One of the things that I learned in 2011 is that spiral notebooks should be avoid where ever possible.'
                }
            ]
        },
    ];

    my $num_tests = scalar @{ $test_cases };
    plan tests => ( 2 * $num_tests ) + 1;

    foreach my $test_case ( @{ $test_cases } )
    {
        my $feed_input = $test_case->{ feed_input };

        my $stories = MediaWords::Crawler::FeedHandler::_get_stories_from_feed_contents_impl(
            $feed_input,
            $test_case->{ media_id },
            $test_case->{ publish_date }
        );

        foreach my $story ( @$stories )
        {
            undef( $story->{ collect_date } );
        }

        my $test_output = $test_case->{ test_output };
        foreach my $element ( @$test_output )
        {
            undef( $element->{ collect_date } );
        }

        is( $stories->[ 0 ]->{ publish_date }, $test_case->{ test_output }->[ 0 ]->{ publish_date }, 'publish_date' );

        cmp_deeply( $stories, $test_case->{ test_output } );

    }
}

main();
