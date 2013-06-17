package MediaWords::CM::GuessDate;

# guess the date of a spidered story using a combination of the story url, html, and
# a first guess date

# FIXME EST to GMT

use strict;
use warnings;

use MediaWords::CM::GuessDate::Result;

use DateTime;
use Date::Parse;
use HTML::TreeBuilder::LibXML;
use LWP::Simple;
use Regexp::Common qw(time);
use Date::Parse;

use MediaWords::CommonLibs;
use MediaWords::CM::GuessDate;
use MediaWords::DB;

# threshold of number of days a guess date can be off from the existing
# story date without dropping the guess
use constant DATE_GUESS_THRESHOLD => 14;

# Default hour to use when no time is present (minutes and seconds are going to both be 0)
# (12:00:00 because it looks nice and more or less fits within the same day in both California and Moscow)
use constant DEFAULT_HOUR => 12;

# only use the date from these guessing functions if the date is within DATE_GUESS_THRESHOLD days
# of the existing date for the story
my $_date_guess_functions = [
    {
        name     => 'guess_by_dc_date_issued',
        function => \&_guess_by_dc_date_issued
    },
    {
        name     => 'guess_by_dc_created',
        function => \&_guess_by_dc_created
    },
    {
        name     => 'guess_by_meta_publish_date',
        function => \&_guess_by_meta_publish_date
    },
    {
        name     => 'guess_by_og_article_published_time',
        function => \&_guess_by_og_article_published_time
    },
    {
        name     => '_guess_by_sailthru_date',
        function => \&_guess_by_sailthru_date
    },
    {
        name     => 'guess_by_storydate',
        function => \&_guess_by_storydate
    },
    {
        name     => 'guess_by_datatime',
        function => \&_guess_by_datatime
    },
    {
        name     => 'guess_by_datetime_pubdate',
        function => \&_guess_by_datetime_pubdate
    },
    {
        name     => 'guess_by_url_and_date_text',
        function => \&_guess_by_url_and_date_text
    },
    {
        name     => 'guess_by_url',
        function => \&_guess_by_url
    },
    {
        name     => 'guess_by_class_date',
        function => \&_guess_by_class_date
    },
    {
        name     => 'guess_by_date_text',
        function => \&_guess_by_date_text
    },
    {
        name     => 'guess_by_existing_story_date',
        function => \&_guess_by_existing_story_date
    },
];

# return the first in a list of nodes matching the xpath pattern
sub _find_first_node
{
    my ( $html_tree, $xpath ) = @_;

    my @nodes = $html_tree->findnodes( $xpath );

    my $node = pop @nodes;

    return $node;
}

# get HTML::TreeBuilder::LibXML object representing the html
sub _get_html_tree
{
    my ( $html ) = @_;

    my $html_tree = HTML::TreeBuilder::LibXML->new;
    $html_tree->ignore_unknown( 0 );
    $html_tree->parse_content( $html );

    return $html_tree;
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
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//meta[@name="DC.date.issued"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <li property="dc:date dc:created" content="2012-01-17T05:51:44-07:00" datatype="xsd:dateTime" class="created">January 17, 2012</li>
sub _guess_by_dc_created
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//li[@property="dc:date dc:created"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <meta name="item-publish-date" content="Wed, 28 Dec 2011 17:39:00 GMT" />
sub _guess_by_meta_publish_date
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//meta[@name="item-publish-date"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <meta property="article:published_time" content="2012-01-17T12:00:00-05:00" />
sub _guess_by_og_article_published_time
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//meta[@property="article:published_time"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <meta name="sailthru.date" content="Tue, 11 Sep 2012 11:37:49 -0400">
sub _guess_by_sailthru_date
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//meta[@name="sailthru.date"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <p class="storydate">Tue, Dec 6th 2011 7:28am</p>
sub _guess_by_storydate
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//p[@class="storydate"]' ) )
    {
        return $node->as_text;
    }
}

# <span class="date" data-time="1326839460">Jan 17, 2012 10:31 pm UTC</span>
sub _guess_by_datatime
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//span[@class="date" and @data-time]' ) )
    {
        return $node->attr( 'data-time' );
    }
}

# <time datetime="2012-06-06" pubdate="foo" />
sub _guess_by_datetime_pubdate
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//time[@datetime and @pubdate]' ) )
    {
        return $node->attr( 'datetime' );
    }
}

# look for a date in the story url
sub _guess_by_url
{
    my ( $story, $html, $html_tree ) = @_;

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
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//*[@class="date"]' ) )
    {
        return $node->as_text;
    }

}

# Matches a (likely) publication date(+time) in the HTML passed as a parameter; returns timestamp on success,
# undef if no date(+time) was found
# FIXME use return values of Regexp::Common::time to form a standardized date
# FIXME prefer date-time timestamps over date-only timestamps
sub timestamp_from_html($)
{
    my $html = shift;

    unless ( $html )
    {
        return undef;
    }

    $html =~ s/&nbsp;/ /g;
    $html =~ s|<br ?/?>| |g;

    my $month_names   = [ qw/january february march april may june july august september october november december/ ];
    my $weekday_names = [ qw/monday tuesday wednesday thursday friday saturday sunday/ ];

    push( @{ $month_names },   map { substr( $_, 0, 3 ) } @{ $month_names } );
    push( @{ $weekday_names }, map { substr( $_, 0, 3 ) } @{ $weekday_names } );

    my $month_names_pattern   = join( '|', @{ $month_names } );
    my $weekday_names_pattern = join( '|', @{ $weekday_names } );

    # Common patterns for date / time parts
    my $pattern_timezone    = qr/(?<timezone>\w{1,4}T)/i;                               # e.g. "PT", "GMT", "EEST", "AZOST"
    my $pattern_hour        = qr/(?<hour>\d\d?)/i;                                      # e.g. "12", "9", "24"
    my $pattern_minute      = qr/(?<minute>\d\d)/i;                                     # e.g. "01", "59"
    my $pattern_second      = qr/(?<second>\d\d)/i;                                     # e.g. "01", "59"
    my $pattern_hour_minute = qr/(?<hours_minutes>$pattern_hour\:$pattern_minute)/i;    # e.g. "12:50", "9:39"
    my $pattern_hour_minute_second =
      qr/(?<hours_minutes_seconds>$pattern_hour\:$pattern_minute\:$pattern_second)/i;    # e.g. "12:50:00"
    my $pattern_month         = qr/(?<month>(:?0?[1-9]|1[012]))/i;          # e.g. "12", "01", "7"
    my $pattern_month_names   = qr/(?<month>$month_names_pattern)/i;        # e.g. "January", "February", "Jan", "Feb"
    my $pattern_weekday_names = qr/(?<weekday>$weekday_names_pattern)/i;    # e.g. "Monday", "Tuesday", "Mon", "Tue"
    my $pattern_day_of_month = qr/(?:(?<day>(?:0?[1-9]|[12][0-9]|3[01]))(?:st|th)?)/i;    # e.g. "23", "02", "9th", "1st"
    my $pattern_year         = qr/(?<year>2?0?\d\d)/i;                                    # e.g. "2001", "2023"
    my $pattern_am_pm        = qr/(?<am_pm>[AP]\.?M\.?)/i;                                # e.g. "AM", "PM"
    my $pattern_comma        = qr/(?:,)/i;                                                # e.g. ","

    # Patterns that match both date *and* time
    my @date_time_patterns = (

        #
        # Date + time patterns
        #

        # 9:24 pm, Tuesday, August 28, 2012
        qr/(
            $pattern_hour_minute
            \s*
            $pattern_am_pm?
            \s*
            $pattern_comma?
            \s+
            $pattern_weekday_names
            \s*
            $pattern_comma?
            \s+
            $pattern_month_names
            \s+
            $pattern_day_of_month
            \s*
            $pattern_comma?
            \s+
            $pattern_year
            )/ix,

        # 11.06.2012 11:56 p.m.
        # or
        # 11/06/2012 08:30:20 PM PST
        qr{(
            $pattern_month
            [\./]
            $pattern_day_of_month
            [\./]
            $pattern_year
            \s+
            $pattern_hour_minute
            (?:\:$pattern_second)?
            (?:\s*$pattern_am_pm)?
            (?:\s+$pattern_timezone)?
            )}ix,

        # January 17(th), 2012, 2:31 PM EST
        qr/(
            $pattern_month_names
            \s+
            $pattern_day_of_month?
            \s*
            (?:,|\s+at)?                # optional comma or "at"
            \s+
            $pattern_year
            \s*
            $pattern_comma?
            \s+
            $pattern_hour_minute
            \s*
            $pattern_am_pm?
            \s+
            $pattern_timezone?
            )/ix,

        # Tue, 28 Aug 2012 21:24:00 GMT (RFC 822)
        # or
        # Wednesday, 29 August 2012 03:55
        # or
        # 7th November 2012
        qr/(
            (?:$pattern_weekday_names
            \s*
            $pattern_comma
            \s+)?
            $pattern_day_of_month
            \s+
            $pattern_month_names
            \s+
            $pattern_year
            (?:
                \s+
                $pattern_hour_minute
                (?:\:$pattern_second)?
                (?:\s+$pattern_timezone)?
            )?
            )/ix,

        # Thursday May 30, 2013 2:14 AM PT (sfgate.com header)
        qr/(
            $pattern_weekday_names
            \s+
            $pattern_month_names
            \s+
            $pattern_day_of_month
            \s*
            $pattern_comma?
            \s+
            $pattern_year
            \s+
            $pattern_hour_minute
            \s*
            $pattern_am_pm
            \s+
            $pattern_timezone
            )/ix,

        #
        # Date-only patterns
        #

        # January 17, 2012
        qr/(
            $pattern_month_names
            \s+
            $pattern_day_of_month?
            \s*
            (?:,|\s+at)?                # optional comma or "at"
            \s+
            $pattern_year
            )/ix,

    );

    # Create one big regex out of date patterns as we want to know the order of
    # various dates appearing in the HTML page
    my $date_pattern = join( '|', @date_time_patterns );
    $date_pattern = '(' . $date_pattern . ')';

    my @matched_timestamps = ();

    my %mon2num = qw(
      jan 1    feb 2  mar 3  apr 4  may 5  jun 6
      jul 7    aug 8  sep 9  oct 10  nov 11 dec 12
      january 1  february 2  march 3  april 4  may 5  june 6
      july 7  august 8  september 9  october 10  november 11 december 12
    );

    # Attempt to match both date *and* time first for better accuracy
    while ( $html =~ /$date_pattern/g )
    {

        # say STDERR "Matched string: $1";

        # Collect date parts
        my $d_year = $+{ year } + 0;
        if ( $d_year < 100 )
        {    # two digits, e.g. "12"
            $d_year += 2000;
        }
        my $d_month = lc( $+{ month } );
        if ( $mon2num{ $d_month } )
        {
            $d_month = $mon2num{ $d_month };
        }
        else
        {
            $d_month = ( $d_month + 0 );
        }
        my $d_day   = ( defined $+{ day } ? $+{ day } + 0     : 0 );
        my $d_am_pm = ( $+{ am_pm }       ? lc( $+{ am_pm } ) : '' );
        my $d_hour  = ( $+{ hour }        ? $+{ hour } + 0    : DEFAULT_HOUR );
        if ( $d_am_pm )
        {
            $d_hour = ( $d_hour % 12 ) + ( ( $d_am_pm eq 'am' ) ? 0 : 12 );
        }
        my $d_minute   = ( $+{ minute }   ? $+{ minute } + 0 : 0 );
        my $d_second   = ( $+{ second }   ? $+{ second } + 0 : 0 );
        my $d_timezone = ( $+{ timezone } ? $+{ timezone }   : 'GMT' );

        if ( uc( $d_timezone ) eq 'PT' )
        {

            # FIXME assume at Pacific Time (PT) is always PDT and not PST
            # (no easy way to determine which exact timezone is currently in America/Los_Angeles)
            $d_timezone = 'PDT';
        }

        # Create a date parseable by Date::Parse correctly, e.g. 2013-05-13 23:52:00 GMT
        my $date_string = sprintf( '%04d-%02d-%02d %02d:%02d:%02d %s',
            $d_year, $d_month, $d_day, $d_hour, $d_minute, $d_second, $d_timezone );
        my $time = str2time( $date_string );

        if ( $time )
        {
            push( @matched_timestamps, $time );
        }
    }

    # say STDERR "Matched timestamps: " . Dumper(@matched_timestamps);

    if ( scalar( @matched_timestamps ) == 0 )
    {

        # no timestamps found
        return undef;
    }

    # If there are 2+ dates on the page and the first one looks more or less like now
    # (+/- 1 day to reduce timezone ambiguity), then it's probably a website's header
    # with today's date and it should be ignored
    if ( scalar( @matched_timestamps ) >= 2 )
    {
        if (   ( time() > $matched_timestamps[ 0 ] and time() - $matched_timestamps[ 0 ] <= ( 60 * 60 * 24 ) )
            or ( $matched_timestamps[ 0 ] > time() and $matched_timestamps[ 0 ] - time() <= ( 60 * 60 * 24 ) ) )
        {
            return $matched_timestamps[ 1 ];
        }
    }

    return $matched_timestamps[ 0 ];
}

# look for any month name followed by something that looks like a date
sub _guess_by_date_text
{
    my ( $story, $html, $html_tree ) = @_;

    return timestamp_from_html( $html );
}

# if _guess_by_url returns a date, use _guess_by_date_text if the days agree
sub _guess_by_url_and_date_text
{
    my ( $story, $html, $html_tree ) = @_;

    my $url_date = _guess_by_url( $story, $html, $html_tree );

    return unless defined( $url_date );

    my $text_date = _make_unix_timestamp( _guess_by_date_text( $story, $html, $html_tree ) );

    if ( defined( $text_date ) and ( $text_date > $url_date ) and ( ( $text_date - $url_date ) < 86400 ) )
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
    my ( $story, $html, $html_tree ) = @_;

    return $story->{ publish_date };
}

# if the date is a number, assume it is an UNIX timestamp and return it; otherwise, parse
# it and return the UNIX timestamp
sub _make_unix_timestamp
{
    my ( $date ) = @_;

    return undef unless ( $date );

    return $date if ( $date =~ /^\d+$/ );

    my $timestamp = Date::Parse::str2time( $date, 'GMT' );

    return undef unless ( $timestamp );

    $timestamp = _round_midnight_to_noon( $timestamp );

    # if we have to use a default timezone, deal with daylight savings
    if ( ( $date =~ /T$/ ) && ( my $is_daylight_savings = ( gmtime( $timestamp ) )[ 8 ] ) )
    {
        $timestamp += 3600;
    }

    return $timestamp;
}

# Returns true if date guessing should not be done on this page
# (404 Not Found, is a tag page, search page, wiki page, etc.)
sub _guessing_is_inapplicable($$$)
{
    my ( $db, $story, $html ) = @_;

    unless ( $html )
    {
        return 1;
    }

    return 0;
}

# guess the date for the story by cycling through the $_date_guess_functions one at a time.
# returns MediaWords::CM::GuessDate::Result object
sub guess_date($$$;$)
{
    my ( $db, $story, $html, $use_threshold ) = @_;

    my $result = MediaWords::CM::GuessDate::Result->new();

    if ( _guessing_is_inapplicable( $db, $story, $html ) )
    {
        # Inapplicable
        $result->{ result } = MediaWords::CM::GuessDate::Result::INAPPLICABLE;
        return $result;
    }

    my $html_tree = _get_html_tree( $html );

    my $story_timestamp = _make_unix_timestamp( $story->{ publish_date } );

    for my $date_guess_function ( @{ $_date_guess_functions } )
    {
        if ( my $timestamp = _make_unix_timestamp( $date_guess_function->{ function }->( $story, $html, $html_tree ) ) )
        {
            if ( $use_threshold && ( abs( $timestamp - $story_timestamp ) < ( DATE_GUESS_THRESHOLD * 86400 ) ) )
            {
                next;
            }

            # Found
            $result->{ result }       = MediaWords::CM::GuessDate::Result::FOUND;
            $result->{ guess_method } = $date_guess_function->{ name };
            $result->{ timestamp }    = $timestamp;
            $result->{ date }         = DateTime->from_epoch( epoch => $timestamp )->datetime;
            return $result;
        }
    }

    # Not found
    $result->{ result } = MediaWords::CM::GuessDate::Result::NOT_FOUND;
    return $result;
}

1;
