use strict;
use warnings;

use Test::NoWarnings;
use Test::More tests => 13 + 1;
use Test::Deep;

use utf8;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

# Integer constants (in case Date::Parse::str2time fails)
use constant _TIMESTAMP_12_00_GMT => 1326801600;    # Tue, 17 Jan 2012 12:00:00 GMT; for dates without time / timezone
use constant _TIMESTAMP_12_00_EST => 1326819600;    # Tue, 17 Jan 2012 12:00:00 EST

BEGIN { use_ok 'MediaWords::CM::GuessDate' }

my $db = MediaWords::DB::connect_to_db();

# Shorthand
sub _gt($;$$)
{
    my ( $html, $story_url, $story_publish_date ) = @_;
    $story_url          ||= 'http://www.example.com/story.html';
    $story_publish_date ||= 'unknown';
    my $story = { url => $story_url, publish_date => $story_publish_date };
    return MediaWords::CM::GuessDate::guess_timestamp( $db, $story, $html );
}

sub test_dates
{
    is( _gt( '<meta name="DC.date.issued" content="2012-01-17T12:00:00-05:00" />' ),
        _TIMESTAMP_12_00_EST, 'guess_by_dc_date_issued' );
    is(
        _gt(
            '<li property="dc:date dc:created" ' . 'content="2012-01-17T12:00:00-05:00" ' .
              'datatype="xsd:dateTime" class="created">' . 'January 17, 2012</li>'
        ),
        _TIMESTAMP_12_00_EST,
        'guess_by_dc_created'
    );
    is( _gt( '<meta name="item-publish-date" content="Tue, 17 Jan 2012 12:00:00 EST" />' ),
        _TIMESTAMP_12_00_EST, 'guess_by_meta_publish_date' );

    # Assume that the timezone is GMT
    is( _gt( '<p class="storydate">Tue, Jan 17th 2012</p>' ), _TIMESTAMP_12_00_GMT, 'guess_by_storydate' );

    is( _gt( '<span class="date" data-time="1326819600">Jan 17, 2012 12:00 pm EST</span>' ),
        _TIMESTAMP_12_00_EST, 'guess_by_datatime' );

    # FIXME _guess_by_datetime_pubdate() ignores contents, uses @datetime instead;
    # and @datetime assumes that the timezone is GMT.
    is( _gt( '<time datetime="2012-01-17" pubdate>Jan 17, 2012 12:00 pm EST</time>' ),
        _TIMESTAMP_12_00_GMT, 'guess_by_datetime_pubdate' );

    is( _gt( '<p>Hello!</p>', 'http://www.example.com/news/2012/01/17/hello.html' ), _TIMESTAMP_12_00_GMT, 'guess_by_url' );

    # Expected to prefer the date in text, fallback to the date in URL
    is( _gt( 'Jan 17th, 2012, 05:00 AM GMT', 'http://www.example.com/news/2012/01/17/hello.html' ),
        _TIMESTAMP_12_00_GMT, 'guess_by_url_and_date_text in URL' );
    is( _gt( 'Jan 17th, 2012, 12:00 PM EST', 'http://www.example.com/news/2012/01/17/hello.html' ),
        _TIMESTAMP_12_00_EST, 'guess_by_url_and_date_text in text and URL' );

    is( _gt( '<p class="date">Jan 17, 2012</p>' ), _TIMESTAMP_12_00_GMT, 'guess_by_class_date' );
    is( _gt( '<p>foo bar</p><p class="dateline>published on Jan 17th, 2012, 12:00 PM EST' ),
        _TIMESTAMP_12_00_EST, 'guess_by_date_text' );
    is( _gt( '<p>Hey!</p>', undef, '2012-01-17T12:00:00-05:00' ), _TIMESTAMP_12_00_EST, 'guess_by_existing_story_date' );
}

sub main
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_dates();
}

main();

