#!/usr/bin/env perl

use strict;
use warnings;

# test TM::Mine::_import_month_within_respider_date

use English '-no_match_vars';

use Test::More;

use Time::Piece;

use MediaWords::ImportStories::Dummy;

sub test_parse_story_date
{
    my $import = MediaWords::ImportStories::Dummy->new( db => {}, media_id => 1 );

    $import->{ date_pattern } = 'BOGUS';

    my $got_date = $import->parse_date_pattern( 'FOO' );

    ok ( !$got_date, "no match" );

    $import->date_pattern( 'the date is: (.*).  the author is:' );
    $got_date = $import->parse_date_pattern( 'the date is: 2020-05-12.  the author is:' );
    is( $got_date, '2020-05-12 00:00:00', 'iso date' );

    $import->date_pattern( 'published on (.*)' );
    $got_date = $import->parse_date_pattern( 'published on June 1, 2020' );
    is( $got_date, '2020-06-01 00:00:00', 'month name' );
}

sub test_generate_story
{
    my $import = MediaWords::ImportStories::Dummy->new( db => {}, media_id => 1 );

    $import->date_pattern( 'published: (.*) -' );

    my $title = 'FOO TITLE';
    my $url = 'http://foo.bar';
    my $content = "<title>$title</title> published: May 12 - Foo bar.";
    my $got_story = $import->generate_story( $content, $url );

    is( $got_story->{ content }, $content );
    is( $got_story->{ title }, $title );
    is( $got_story->{ url }, $url );
    is( $got_story->{ publish_date }, Time::Piece->new()->year() . '-05-12 00:00:00');
}

sub main
{
    test_parse_story_date();
    test_generate_story();

    done_testing();
}

main();
