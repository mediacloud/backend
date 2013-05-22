package MediaWords::CM::GuessDate;

# guess the date of a spidered story using a combination of the story url, html, and
# a first guess date

# FIXME EST to GMT

use strict;

use DateTime;
use Date::Parse;
use HTML::TreeBuilder::LibXML;

use MediaWords::CommonLibs;
use MediaWords::CM::GuessDate;
use MediaWords::DB;

# threshhold of number of days a guess date can be off from the existing
# story date without dropping the guess
my $_date_guess_threshhold = 14;

# Integer constants (in case Date::Parse::str2time fails)
use constant _TIMESTAMP_12_00_EST => 1326819600;    # Tue, 17 Jan 2012 12:00:00 EST
use constant _TIMESTAMP_05_00_GMT => 1326801600;    # Tue, 17 Jan 2012 12:00:00 GMT; for dates without time / timezone

# only use the date from these guessing functions if the date is within $_date_guess_threshhold days
# of the existing date for the story
my $_date_guess_functions = [
    {
        name     => 'guess_by_dc_date_issued',
        function => \&_guess_by_dc_date_issued,
        test     => '<meta name="DC.date.issued" content="2012-01-17T12:00:00-05:00" />',
        expected => _TIMESTAMP_12_00_EST
    },
    {
        name     => 'guess_by_dc_created',
        function => \&_guess_by_dc_created,
        test =>
'<li property="dc:date dc:created" content="2012-01-17T12:00:00-05:00" datatype="xsd:dateTime" class="created">January 17, 2012</li>',
        expected => _TIMESTAMP_12_00_EST
    },
    {
        name     => 'guess_by_meta_publish_date',
        function => \&_guess_by_meta_publish_date,
        test     => '<meta name="item-publish-date" content="Tue, 17 Jan 2012 12:00:00 EST" />',
        expected => _TIMESTAMP_12_00_EST
    },
    {
        name     => 'guess_by_storydate',
        function => \&_guess_by_storydate,
        test     => '<p class="storydate">Tue, Jan 17th 2012</p>',

        # Assume that the timezone is GMT
        expected => _TIMESTAMP_05_00_GMT
    },
    {
        name     => 'guess_by_datatime',
        function => \&_guess_by_datatime,
        test     => '<span class="date" data-time="1326819600">Jan 17, 2012 12:00 pm EST</span>',
        expected => _TIMESTAMP_12_00_EST
    },
    {
        name     => 'guess_by_datetime_pubdate',
        function => \&_guess_by_datetime_pubdate,
        test     => '<time datetime="2012-01-17" pubdate>Jan 17, 2012 12:00 pm EST</time>',

        # FIXME _guess_by_datetime_pubdate() ignores contents, uses @datetime instead;
        # and @datetime assumes that the timezone is GMT.
        expected => _TIMESTAMP_05_00_GMT
    },
    {
        name     => 'guess_by_url_and_date_text',
        function => \&_guess_by_url_and_date_text,
        expected => _TIMESTAMP_12_00_EST
    },
    {
        name     => 'guess_by_url',
        function => \&_guess_by_url,
        expected => _TIMESTAMP_12_00_EST
    },
    {
        name     => 'guess_by_class_date',
        function => \&_guess_by_class_date,
        test     => '<p class="date">Jan 17, 2012</p>',
        expected => _TIMESTAMP_05_00_GMT
    },
    {
        name     => 'guess_by_date_text',
        function => \&_guess_by_date_text,
        test     => '<p>foo bar</p><p class="dateline>published on Jan 17th, 2012, 12:00 PM EST',
        expected => _TIMESTAMP_12_00_EST
    },
    {
        name     => 'guess_by_existing_story_date',
        function => \&_guess_by_existing_story_date,
        expected => _TIMESTAMP_12_00_EST
    },
];

# return the first in a list of nodes matching the xpath pattern
sub _find_first_node
{
    my ( $tree, $xpath ) = @_;

    my @nodes = $tree->findnodes( $xpath );

    my $node = pop @nodes;

    return $node;
}

# get HTML::TreeBuilder::LibXML object representing the html
sub _get_xpath
{
    my ( $html ) = @_;

    my $xpath = HTML::TreeBuilder::LibXML->new;
    $xpath->ignore_unknown( 0 );
    $xpath->parse_content( $html );

    return $xpath;
}

# return true if the args are valid date arguments.  assume a date has to be between 2000 and 2020.
sub _validate_date_parts
{
    my ( $year, $month, $day ) = @_;

    return 0 if ( ( $year < 2000 ) || ( $year > 2020 ) );

    return Date::Parse::str2time( "$year-$month-$day 12:00 PM", 'GMT' );
}

# if the date is exactly midnight, round it to noon because noon is a better guess of the publication time
sub _round_midnight_to_noon
{
    my ( $date ) = @_;

    my @t = gmtime( $date );

    if ( !$t[ 0 ] && !$t[ 1 ] && !$t[ 2 ] )
    {
        return $date + 12 * 3600;
    }
    else
    {
        return $date;
    }
}

# <meta name="DC.date.issued" content="2011-12-16T13:56:00-08:00" />
sub _guess_by_dc_date_issued
{
    my ( $story, $html, $xpath ) = @_;

    if ( my $node = _find_first_node( $xpath, '//meta[@name="DC.date.issued"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <li property="dc:date dc:created" content="2012-01-17T05:51:44-07:00" datatype="xsd:dateTime" class="created">January 17, 2012</li>
sub _guess_by_dc_created
{
    my ( $story, $html, $xpath ) = @_;

    if ( my $node = _find_first_node( $xpath, '//li[@property="dc:date dc:created"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <meta name="item-publish-date" content="Wed, 28 Dec 2011 17:39:00 GMT" />
sub _guess_by_meta_publish_date
{
    my ( $story, $html, $xpath ) = @_;

    if ( my $node = _find_first_node( $xpath, '//meta[@name="item-publish-date"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <p class="storydate">Tue, Dec 6th 2011 7:28am</p>
sub _guess_by_storydate
{
    my ( $story, $html, $xpath ) = @_;

    if ( my $node = _find_first_node( $xpath, '//p[@class="storydate"]' ) )
    {
        return $node->as_text;
    }
}

# <span class="date" data-time="1326839460">Jan 17, 2012 10:31 pm UTC</span>
sub _guess_by_datatime
{
    my ( $story, $html, $xpath ) = @_;

    if ( my $node = _find_first_node( $xpath, '//span[@class="date" and @data-time]' ) )
    {
        return $node->attr( 'data-time' );
    }
}

# <time datetime="2012-06-06" pubdate="foo" />
sub _guess_by_datetime_pubdate
{
    my ( $story, $html, $xpath ) = @_;

    if ( my $node = _find_first_node( $xpath, '//time[@datetime and @pubdate]' ) )
    {
        return $node->attr( 'datetime' );
    }
}

# look for a date in the story url
sub _guess_by_url
{
    my ( $story, $html, $xpath ) = @_;

    my $url = $story->{ url };
    my $redirect_url = $story->{ redirect_url } || $url;

    if ( ( $url =~ m~(20\d\d)/(\d\d)/(\d\d)~ ) || ( $redirect_url =~ m~(20\d\d)/(\d\d)/(\d\d)~ ) )
    {
        my $date = _validate_date_parts( $1, $2, $3 );
        return $date if ( $date );
    }

    if ( ( $url =~ m~/(20\d\d)(\d\d)(\d\d)/~ ) || ( $redirect_url =~ m~(20\d\d)(\d\d)(\d\d)~ ) )
    {
        return _validate_date_parts( $1, $2, $3 );
    }
}

# look for any element with a class='date' attribute
sub _guess_by_class_date
{
    my ( $story, $html, $xpath ) = @_;

    if ( my $node = _find_first_node( $xpath, '//*[@class="date"]' ) )
    {
        return $node->as_text;
    }

}

# look for any month name followed by something that looks like a date
sub _guess_by_date_text
{
    my ( $story, $html, $xpath ) = @_;

    my $month_names = [ qw/january february march april may june july august september october november december/ ];

    push( @{ $month_names }, map { substr( $_, 0, 3 ) } @{ $month_names } );

    my $month_names_pattern = join( '|', @{ $month_names } );

    #  January 17, 2012 2:31 PM EST
    if ( $html =~
        /((?:$month_names_pattern)\s*\d\d?(?:st|th)?(?:,|\s+at)?\s+20\d\d(?:,?\s*\d\d?\:\d\d\s*[AP]M(?:\s+\w\wT)?)?)/i )
    {
        my $date_string = $1;

        return $date_string;
    }
}

# if _guess_by_url returns a date, use _guess_by_date_text if the days agree
sub _guess_by_url_and_date_text
{
    my ( $story, $html, $xpath ) = @_;

    my $url_date = _guess_by_url( $story, $html, $xpath );

    return if ( !$url_date );

    my $text_date = _make_epoch_date( _guess_by_date_text( $story, $html, $xpath ) );

    if ( ( $text_date > $url_date ) and ( ( $text_date - $url_date ) < 86400 ) )
    {
        return $text_date;
    }
    else
    {
        return $url_date;
    }
}

# just return the existing publish_date of the story.
# this is useful as a last resort so that we can keep
# track of the '_guess_by_existing_story_date' method
sub _guess_by_existing_story_date
{
    my ( $story, $html, $xpath ) = @_;

    return $story->{ publish_date };
}

# if the date is a number, assume it is an epoch date and return it; otherwise, parse
# it and return the epoch date
sub _make_epoch_date
{
    my ( $date ) = @_;

    return undef unless ( $date );

    return $date if ( $date =~ /^\d+$/ );

    my $epoch = Date::Parse::str2time( $date, 'GMT' );

    return undef unless ( $epoch );

    $epoch = _round_midnight_to_noon( $epoch );

    # if we have to use a default timezone, deal with daylight savings
    if ( ( $date =~ /T$/ ) && ( my $is_daylight_savings = ( gmtime( $epoch ) )[ 8 ] ) )
    {
        $epoch += 3600;
    }

    return $epoch;
}

# guess the date for the story by cycling through the $_date_guess_functions one at a time.  return the date in epoch format.
sub guess_date
{
    my ( $db, $story, $html, $use_threshold ) = @_;

    my $xpath = _get_xpath( $html );

    my $story_epoch_date = _make_epoch_date( $story->{ publish_date } );

    for my $date_guess_function ( @{ $_date_guess_functions } )
    {
        if ( my $date = _make_epoch_date( $date_guess_function->{ function }->( $story, $html, $xpath ) ) )
        {
            if ( $use_threshold && ( abs( $date - $story_epoch_date ) < ( $_date_guess_threshhold * 86400 ) ) )
            {
                next;
            }
            my $epoch_date = DateTime->from_epoch( epoch => $date )->datetime;
            return wantarray ? ( $date_guess_function->{ name }, $epoch_date ) : $epoch_date;
        }
    }

    return undef;
}

# test each date parser
sub test_date_parsers
{
    my $i = 0;
    for my $date_guess_function ( @{ $_date_guess_functions } )
    {
        if ( my $test = $date_guess_function->{ test } )
        {
            my $xpath = _get_xpath( $test );

            my $story = { url => $test };
            my $date = _make_epoch_date( $date_guess_function->{ function }->( $story, $test, $xpath ) );

            if ( defined( $date ) and ( $date ne $date_guess_function->{ expected } ) )
            {
                die( "test $i [ $test ] failed: got date '$date' expected '$date_guess_function->{ expected }'" );
            }
        }

        $i++;
    }
}

1;
