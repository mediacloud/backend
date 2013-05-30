use strict;
use warnings;

use Test::NoWarnings;
use Test::More tests => 29 + 1;
use Test::Deep;

use utf8;

use Modern::Perl "2012";
use MediaWords::CommonLibs;

# Integer constants (in case Date::Parse::str2time fails)
use constant _TIMESTAMP_12_00_GMT => 1326801600;    # Tue, 17 Jan 2012 12:00:00 GMT; for dates without time / timezone
use constant _TIMESTAMP_12_00_EST => 1326819600;    # Tue, 17 Jan 2012 12:00:00 EST

BEGIN { use_ok 'MediaWords::CM::GuessDate' }
BEGIN { use_ok 'Date::Parse' }
BEGIN { use_ok 'LWP::Simple' }

my $db = MediaWords::DB::connect_to_db();

# Shorthand for guess_timestamp()
sub _gt($;$$)
{
    my ( $html, $story_url, $story_publish_date ) = @_;
    $story_url          ||= 'http://www.example.com/story.html';
    $story_publish_date ||= 'unknown';
    my $story = { url => $story_url, publish_date => $story_publish_date };
    return MediaWords::CM::GuessDate::guess_timestamp( $db, $story, $html );
}

# Shorthand for guess_timestamp() by fetching the URL
sub _gt_url($;$)
{
    my ( $story_url, $story_publish_date ) = @_;

    my $html = get( $story_url );

    #die "Unable to fetch URL $story_url because: $!\n" unless defined $html;

    return _gt( $html, $story_url, $story_publish_date );
}

# Shorthand for timestamp_from_html()
sub _ts_from_html($)
{
    my $html = shift;

    return MediaWords::CM::GuessDate::timestamp_from_html( $html );
}

# Shortcut for making UNIX timestamps out of RFC 822 dates
sub _ts($)
{
    my $date = shift;
    return Date::Parse::str2time( $date );
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

    is( _gt( '<meta property="article:published_time" content="2012-01-17T12:00:00-05:00" />' ),
        _TIMESTAMP_12_00_EST, 'guess_by_og_article_published_time' );

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

# Redo into local tests
sub test_live_urls
{

    # Wednesday, 29 August 2012 03:55
    is(
        _gt_url(
'http://davisvanguard.org/index.php?option=com_content&view=article&id=5650:proposition-36-would-modify-californias-three-strikes-law&Itemid=100'
        ),
        _ts( 'Wed, 29 Aug 12 03:55:00 +0000' ),
        'live_url: W, [dj] F Y H:i'
    );

    # HTTP Last-Modified
    is(
        _gt_url( 'http://www.texaspolicy.com/sites/default/files/documents/2012-10-13-Reuters-ROC.pdf' ),
        _ts( 'Wed, 17 Oct 2012 23:59:25 GMT' ),
        'live_url: HTTP Last-Modified'
    );

    is(
        _gt_url( 'http://www.sfgate.com/opinion/openforum/article/Prop-36-reforms-three-strikes-3822862.php' ),
        _ts( 'Tue, 28 Aug 2012 21:24:00 GMT' ),
        'live_url: sfgate.com'
    );

    is(
        _gt_url( 'http://www.noozhawk.com/article/california_election_statewide_propositions_prop_30/' ),
        _ts( 'Tue, 6 Nov 2012 23:56:00 GMT' ),
        'live_url: noozhawk.com'
    );

    is(
        _gt_url( 'http://punkpedagogy.tumblr.com/post/35204551491/proposition-36-placed-on-the-ballot-in-hopes-of' ),
        _ts( 'Wed, 7 Nov 2012 05:00:00 GMT' ),
        'live_url: punkpedagogy.tumblr.com'
    );

    is(
        _gt_url( 'http://www.cjcj.org/post/adult/corrections/prop/36/modest/and/necessary/three/strikes/reform/index.html' ),
        undef,
        'live_url: 404 Not Found'
    );

    is(
        _gt_url( 'http://www.mercurynews.com/crime-courts/ci_21943951/prop-36-huge-lead-early-returns' ),
        _ts( 'Tue, 6 Nov 2012 20:30:20 PST' ),
        'live_url: mercurynews.com'
    );

}

sub test_date_matching
{
    is(
        _ts_from_html( '<p>Tue, 28 Aug 2012 21:24:00 GMT</p>' ),
        _ts( 'Tue, 28 Aug 2012 21:24:00 GMT' ),
        'date_matching: RFC 822'
    );

    is(
        _ts_from_html( '<p>Thursday May 30, 2013 2:14 AM PT</p>' ),
        _ts( 'Thu, 30 May 2013 02:14:00 PDT' ),
        'date_matching: sfgate.com header'
    );

    is(
        _ts_from_html( '<p>9:24 pm, Tuesday, August 28, 2012</p>' ),
        _ts( 'Tue, 28 Aug 2012 21:24:00 GMT' ),
        'date_matching: sfgate.com article'
    );

    is(
        _ts_from_html( '<p>11.06.2012 11:56 p.m.</p>' ),
        _ts( 'Tue, 6 Nov 2012 23:56:00 GMT' ),
        'date_matching: noozhawk.com article'
    );

    is(
        _ts_from_html( '<p>7th November 2012</p>' ),
        _ts( 'Wed, 7 Nov 2012 05:00:00 GMT' ),
        'date_matching: punkpedagogy.tumblr.com'
    );

    is(
        _ts_from_html(
            <<EOF
            <div id="articleDate" class="articleDate">
                Posted:
                &nbsp;
                11/06/2012 08:30:20 PM PST
            </div>
            <div id="articleDate" class="articleSecondaryDate">
                <span class="updated" style="display:none;" title="2012-11-07T11:02:32Z">November 7, 2012 11:2 AM GMT</span>
                Updated:
                &nbsp;
                11/07/2012 03:02:32 AM PST
            </div>
EOF
        ),
        _ts( 'Tue, 6 Nov 2012 20:30:20 PST' ),
        'date_matching: mercurynews.com'
    );
}

sub main
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_dates();
    test_live_urls();
    test_date_matching();
}

main();

