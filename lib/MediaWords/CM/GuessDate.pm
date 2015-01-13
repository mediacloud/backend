package MediaWords::CM::GuessDate;

# guess the date of a spidered story using a combination of the story url, html, and
# a first guess date

use strict;
use warnings;

use MediaWords::CM::GuessDate::Result;

use DateTime;
use Date::Parse;
use HTML::TreeBuilder::LibXML;
use LWP::Simple;
use Regexp::Common qw(time);
use Date::Parse;
use List::Util qw(max min);
use List::MoreUtils qw(any);

use MediaWords::CommonLibs;
use MediaWords::CM::GuessDate;
use MediaWords::DB;
use MediaWords::Util::SQL;

# threshold of number of days a guess date can be before the source link
# story date without dropping the guess
use constant DATE_GUESS_THRESHOLD => 60;

# Default hour to use when no time is present (minutes and seconds are going to both be 0)
# (12:00:00 because it looks nice and more or less fits within the same day in both California and Moscow)
use constant DEFAULT_HOUR => 12;

# only use the date from these guessing functions if the date is within DATE_GUESS_THRESHOLD days
# of the existing date for the story
my $_date_guess_functions = [
    {
        name     => 'guess_by_og_article_published_time',
        function => \&_guess_by_og_article_published_time
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
        name     => 'guess_by_dc_date_issued',
        function => \&_guess_by_dc_date_issued
    },
    {
        name     => 'guess_by_dc_created',
        function => \&_guess_by_dc_created
    },
    {
        name     => 'guess_by_meta_date',
        function => \&_guess_by_meta_date
    },
    {
        name     => 'guess_by_meta_pubdate',
        function => \&_guess_by_meta_pubdate
    },
    {
        name     => 'guess_by_meta_publish_date',
        function => \&_guess_by_meta_publish_date
    },
    {
        name     => 'guess_by_meta_item_publish_date',
        function => \&_guess_by_meta_item_publish_date
    },
    {
        name     => 'guess_by_sailthru_date',
        function => \&_guess_by_sailthru_date
    },
    {
        name     => 'guess_by_abbr_published_updated_date',
        function => \&_guess_by_abbr_published_updated_date
    },
    {
        name     => 'guess_by_span_published_updated_date',
        function => \&_guess_by_span_published_updated_date
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
        name     => 'guess_by_twitter_datatime',
        function => \&_guess_by_twitter_datatime
    },
    {
        name     => 'guess_by_datetime_pubdate',
        function => \&_guess_by_datetime_pubdate
    },
    {
        name     => 'guess_by_class_date',
        function => \&_guess_by_class_date
    },
    {
        name     => 'guess_by_date_text',
        function => \&_guess_by_date_text
    }
];

# return the first in a list of nodes matching the xpath pattern
sub _find_first_node
{
    my ( $html_tree, $xpath ) = @_;

    my @nodes = $html_tree->findnodes( $xpath );

    my $node = shift @nodes;

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

# <meta name="date" content="2012-11-08 04:10:04" />
sub _guess_by_meta_date
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//meta[@name="date"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <meta name="pubdate" content="2012-10-31 13:10:31"/>
sub _guess_by_meta_pubdate
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//meta[@name="pubdate"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <meta name="publish_date" content="Wed, 07 Nov 2012 15:11:54 EST" />
sub _guess_by_meta_publish_date
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//meta[@name="publish-date"]' ) )
    {
        return $node->attr( 'content' );
    }
    if ( my $node = _find_first_node( $html_tree, '//meta[@name="publish_date"]' ) )
    {
        return $node->attr( 'content' );
    }
}

# <meta name="item-publish-date" content="Wed, 28 Dec 2011 17:39:00 GMT" />
sub _guess_by_meta_item_publish_date
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

# <abbr class="updated" title="2013-06-19T16:55:00+03:00">June 19th, 16:55</abbr> (LiveJournal)
sub _guess_by_abbr_published_updated_date
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//abbr[@class="published"][string-length(@title)=25]' ) )
    {
        return $node->attr( 'title' );
    }
    if ( my $node = _find_first_node( $html_tree, '//abbr[@class="updated"][string-length(@title)=25]' ) )
    {
        return $node->attr( 'title' );
    }
}

# <span class="updated" title="2012-11-10T20:47:00-08:00">Posted November 10, 2012 at 8:47 p.m.</span> (vcstar.com)
sub _guess_by_span_published_updated_date
{
    my ( $story, $html, $html_tree ) = @_;

    if ( my $node = _find_first_node( $html_tree, '//span[@class="published"][string-length(@title)=25]' ) )
    {
        return $node->attr( 'title' );
    }
    if ( my $node = _find_first_node( $html_tree, '//span[@class="updated"][string-length(@title)=25]' ) )
    {
        return $node->attr( 'title' );
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

# <small class="time">
#     <a href="/ladygaga/status/318537311698694144" class="tweet-timestamp js-permalink js-nav" title="6:36 PM - 31 Mar 13" >
#         <span class="_timestamp js-short-timestamp " data-time="1364780188" data-long-form="true">31 Mar</span>
#     </a>
# </small>
sub _guess_by_twitter_datatime
{
    my ( $story, $html, $html_tree ) = @_;

    if (
        my $node = _find_first_node(
            $html_tree, '//a[contains(@class, "tweet-timestamp")]/span[contains(@class, "_timestamp") and @data-time]'
        )
      )
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

    if ( ( $url =~ m~(20\d\d)[/-](\d\d)[/-](\d\d)~ ) || ( $redirect_url =~ m~(20\d\d)[/-](\d\d)[/-](\d\d)~ ) )
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
        my $date_string = $node->as_text;

        # Don't trust a date that looks more or less like now
        # (+/- 1 day to reduce timezone ambiguity), then it's probably a website's header
        # with today's date and it should be ignored
        if ( my $timestamp = _make_unix_timestamp( $date_string ) )
        {
            unless ( max( time(), $timestamp ) - min( time(), $timestamp ) <= ( 60 * 60 * 24 ) )
            {
                return $date_string;
            }

        }
    }

    return undef;
}

# Matches a list of date (or date+time) patterns from the arrayref provided
# returns matches on success, empty array on failure
sub _results_from_matching_date_patterns($$)
{
    my ( $html, $date_patterns ) = @_;

    # Create one big regex out of date patterns as we want to know the order of
    # various dates appearing in the HTML page
    my $date_pattern = join( '|', @{ $date_patterns } );
    $date_pattern = '(' . $date_pattern . ')';    # will match parentheses in each of the patterns

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
        my $whole_date = $& || next;

        # say STDERR "Matched string: '$whole_date'";

        # Might get overriden later
        my %result = %+;

        # Collect date parts
        my $d_year = $result{ year } + 0;
        if ( $d_year < 100 )
        {    # two digits, e.g. "12"
            $d_year += 2000;
        }
        my $d_month = lc( $result{ month } );
        $d_month =~ s/\.//gs;    # in case it's "jan."
        if ( $mon2num{ $d_month } )
        {
            $d_month = $mon2num{ $d_month };
        }
        else
        {
            $d_month = ( $d_month + 0 );
        }
        my $d_day      = ( defined $result{ day } ? $result{ day } + 0     : 0 );
        my $d_am_pm    = ( $result{ am_pm }       ? lc( $result{ am_pm } ) : '' );
        my $d_hour     = ( $result{ hour }        ? $result{ hour } + 0    : DEFAULT_HOUR );
        my $d_minute   = ( $result{ minute }      ? $result{ minute } + 0  : 0 );
        my $d_second   = ( $result{ second }      ? $result{ second } + 0  : 0 );
        my $d_timezone = ( $result{ timezone }    ? $result{ timezone }    : 'GMT' );

        if ( uc( $d_timezone ) eq 'PT' )
        {

            # FIXME assume at Pacific Time (PT) is always PDT and not PST
            # (no easy way to determine which exact timezone is currently in America/Los_Angeles)
            $d_timezone = 'PDT';
        }

        $d_am_pm =~ s/\.//gs;
        if ( $d_am_pm )
        {
            $d_hour -= 12 if ( lc( $d_am_pm ) eq 'am' and $d_hour == 12 );
            $d_hour += 12 if ( lc( $d_am_pm ) eq 'pm' and $d_hour != 12 );
        }

        # Create a date parseable by Date::Parse correctly, e.g. 2013-05-13 23:52:00 GMT
        my $date_string = sprintf( '%04d-%02d-%02d %02d:%02d:%02d %s',
            $d_year, $d_month, $d_day, $d_hour, $d_minute, $d_second, $d_timezone );
        my $time = str2time( $date_string ) || str2time( $whole_date );

        if ( $time )
        {

            # Ignore timestamps that are later than "now" (because publication dates are in the past)
            if ( $time < time() )
            {

                # say STDERR "Adding that one";
                push( @matched_timestamps, $time );
            }
        }
    }

    return \@matched_timestamps;
}

# Matches a (likely) publication date(+time) in the HTML passed as a parameter; returns timestamp on success,
# undef if no date(+time) was found
# FIXME use return values of Regexp::Common::time to form a standardized date
sub timestamp_from_html($)
{
    my $html = shift;

    unless ( $html )
    {
        return undef;
    }

    # Remove spaces and line breaks
    $html =~ s/&nbsp;/ /gi;
    $html =~ s|<br ?/?>| |gi;

    # Remove huge <select>s (spotted in event calendars)
    $html =~ s|<select.*?</select>||gis;

    my $month_names   = [ qw/january february march april may june july august september october november december/ ];
    my $weekday_names = [ qw/monday tuesday wednesday thursday friday saturday sunday/ ];

    push( @{ $month_names },   map { substr( $_, 0, 3 ) } @{ $month_names } );            # "jan", "feb", ...
    push( @{ $month_names },   map { substr( $_, 0, 3 ) . '\.?' } @{ $month_names } );    # "jan.", "feb.", ...
    push( @{ $weekday_names }, map { substr( $_, 0, 3 ) } @{ $weekday_names } );          # "mon", "tue", ...

    my $month_names_pattern   = join( '|', @{ $month_names } );
    my $weekday_names_pattern = join( '|', @{ $weekday_names } );

    # Common patterns for date / time parts
    my $pattern_timezone           = qr/(?<timezone>\w{1,4}T)/i;                          # e.g. "PT", "GMT", "EEST", "AZOST"
    my $pattern_hour               = qr/(?<hour>\d\d?)/i;                                 # e.g. "12", "9", "24"
    my $pattern_minute             = qr/(?<minute>\d\d)/i;                                # e.g. "01", "59"
    my $pattern_second             = qr/(?<second>\d\d)/i;                                # e.g. "01", "59"
    my $pattern_hour_minute        = qr/(?:$pattern_hour\:$pattern_minute)/i;             # e.g. "12:50", "9:39"
    my $pattern_hour_minute_second = qr/(?:$pattern_hour_minute\:$pattern_second)/i;      # e.g. "12:50:00"
    my $pattern_month              = qr/(?<month>(:?0?[1-9]|1[012]))/i;                   # e.g. "12", "01", "7"
    my $pattern_month_names   = qr/(?<month>$month_names_pattern)/i;        # e.g. "January", "February", "Jan", "Feb"
    my $pattern_weekday_names = qr/(?<weekday>$weekday_names_pattern)/i;    # e.g. "Monday", "Tuesday", "Mon", "Tue"
    my $pattern_day_of_month        = qr/(?:(?<day>(?:0?[1-9]|[12][0-9]|3[01]))(?:st|th)?)/i; # e.g. "23", "02", "9th", "1st"
    my $pattern_year                = qr/(?<year>2?0?\d\d)/i;                                 # e.g. "2001", "2023"
    my $pattern_am_pm               = qr/(?<am_pm>[AP]\.?M\.?)/i;                             # e.g. "AM", "PM"
    my $pattern_comma               = qr/(?:,)/i;                                             # e.g. ","
    my $pattern_comma_or_at_or_dash = qr/(?:,|\s+at|\s*\-\s*)/i;                              # e.g. ",", "at", "-"
    my $pattern_date_part_separators = qr/[\.\/\-\s]/;                                        # date part separators
    my $pattern_not_digit_or_word_start =
      qr/(?:^|[^\w\d])/i;    # pattern to prevent matching dates in the middle of URLs and such
    my $pattern_not_digit_or_word_end =
      qr/(?:$|[^\w\d])/i;    # pattern to prevent matching dates in the middle of URLs and such

    # Patterns that match both date *and* time
    my @date_time_patterns = (

        #
        # Date + time patterns
        #

        # 9:24 pm, Tuesday, August 28, 2012
        qr{
            $pattern_not_digit_or_word_start
            (
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
            )
            $pattern_not_digit_or_word_end
        }ix,

        # 11.06.2012 11:56 p.m.
        # or
        # 11/06/2012 08:30:20 PM PST
        qr{
            $pattern_not_digit_or_word_start
            (
                $pattern_month
                $pattern_date_part_separators                
                $pattern_day_of_month
                $pattern_date_part_separators
                $pattern_year
                \s+
                $pattern_hour_minute
                (?:\:$pattern_second)?
                (?:\s*$pattern_am_pm)?
                (?:\s+$pattern_timezone)?
            )
            $pattern_not_digit_or_word_end
        }ix,

        # January 17(th), 2012, 2:31 PM EST
        qr{
            $pattern_not_digit_or_word_start
            (
                $pattern_month_names
                \s+
                $pattern_day_of_month?
                \s*
                $pattern_comma_or_at_or_dash?
                \s+
                $pattern_year
                \s*
                $pattern_comma_or_at_or_dash?
                \s+
                $pattern_hour_minute
                (?:\:$pattern_second)?
                \s*
                $pattern_am_pm?
                (?:\s+$pattern_timezone)?
            )
            $pattern_not_digit_or_word_end
        }ix,

        # Tue, 28 Aug 2012 21:24:00 GMT (RFC 822)
        # or
        # Wednesday, 29 August 2012 03:55
        # or
        # 7th November 2012
        qr{
            $pattern_not_digit_or_word_start
            (
                (?:$pattern_weekday_names
                    \s*
                    $pattern_comma
                    \s+
                )?
                $pattern_day_of_month
                \s+
                $pattern_month_names
                \s+
                $pattern_year
                (?:\s+
                    $pattern_hour_minute
                    (?:\:$pattern_second)?
                    (?:\s+$pattern_timezone)?
                )?
            )
            $pattern_not_digit_or_word_end
        }ix,

        # Thursday May 30, 2013 2:14 AM PT (sfgate.com header)
        qr{
            $pattern_not_digit_or_word_start
            (
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
            )
            $pattern_not_digit_or_word_end
        }ix,

    );

    # Patterns that match *only* a date
    my @date_only_patterns = (

        # January 17, 2012
        qr{
            $pattern_not_digit_or_word_start
            (
                $pattern_month_names
                \s+
                $pattern_day_of_month?
                \s*
                $pattern_comma_or_at_or_dash?
                \s+
                $pattern_year
            )
            $pattern_not_digit_or_word_end
        }ix,

        # 11/05/2012
        qr{
            $pattern_not_digit_or_word_start
            (
                $pattern_month
                $pattern_date_part_separators
                $pattern_day_of_month
                $pattern_date_part_separators
                $pattern_year
            )
            $pattern_not_digit_or_word_end
        }ix,

        # 05-may-2012
        qr{
            $pattern_not_digit_or_word_start
            (
                $pattern_day_of_month
                $pattern_date_part_separators
                $pattern_month_names
                $pattern_date_part_separators
                $pattern_year
            )
            $pattern_not_digit_or_word_end
        }ix,

    );

    # Try matching date+time first, retreat to date-only if there are no results
    my @matched_timestamps = ();
    push( @matched_timestamps, @{ _results_from_matching_date_patterns( $html, \@date_time_patterns ) } );
    if ( scalar( @matched_timestamps ) == 0 )
    {
        push( @matched_timestamps, @{ _results_from_matching_date_patterns( $html, \@date_only_patterns ) } );

        if ( scalar( @matched_timestamps ) == 0 )
        {

            # no timestamps found
            return undef;
        }
    }

    # If there are 2+ dates on the page and the first one looks more or less like now
    # (+/- 1 day to reduce timezone ambiguity), then it's probably a website's header
    # with today's date and it should be ignored
    if ( scalar( @matched_timestamps ) >= 2 )
    {
        my $first_timestamp_in_page  = $matched_timestamps[ 0 ];
        my $second_timestamp_in_page = $matched_timestamps[ 1 ];

        if ( max( time(), $first_timestamp_in_page ) - min( time(), $first_timestamp_in_page ) <= ( 60 * 60 * 24 ) )
        {
            return $second_timestamp_in_page;
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

        # Empty page, nothing to date
        return 1;
    }

    my $uri = URI->new( $story->{ url } );
    unless ( $uri )
    {

        # Invalid URL
        return 1;
    }

    $uri = $uri->canonical;
    $uri->fragment( '' );    # remove '#...' ("anchor")
    my $normalized_url = $uri->as_string;

    unless ( $uri->path =~ /[\w\d]/ )
    {

        # Empty path, frontpage of the website
        return 1;
    }

    # for some badly formed urls, ->host() throws an error
    my $host = '';
    eval { $host = $uri->host };

    my $path_for_digit_check = $uri->path_query;
    $path_for_digit_check =~ s/201\d//;

    if (    $normalized_url
        and $host !~ /example\.(com|net|org)$/gi
        and $path_for_digit_check !~ /[0-9]/ )
    {

        # Assume that a dateable story will have a numeric component in its URL's path
        # (either a part of the date like in WordPress's case, or a story ID or something).
        # Tags, search pages, static pages usually don't have a numerals in their URLs
        return 1;
    }

    if ( $host =~ /wikipedia\.org$/gi || $normalized_url =~ /wiki\/index.php/ )
    {

        # ignore wiki pages
        return 1;
    }

    # if ( $host =~ /twitter\.com$/gi and $uri->path !~ /\/?.+?\/status\//gi and $host ne 'blog.twitter.com' )
    # {
    #     # Ignore Twitter user pages (e.g. "twitter.com/ladygaga", not "twitter.com/ladygaga/status/\d*")
    #     return 1;
    # }

    if ( $host =~ /facebook\.com$/gi and $host ne 'blog.facebook.com' )
    {

        # Ignore Facebook pages
        return 1;
    }

    if ( $normalized_url =~ /viewforum\.php/ or $normalized_url =~ /viewtopic\.php/ or $normalized_url =~ /memberlist\.php/ )
    {

        # Ignore phpBB forums
        return 1;
    }

    my @url_segments              = $uri->path_segments;
    my @segments_for_invalidation = qw/
      archive
      archives
      blog-archive
      blog_archive
      search
      tag
      profile
      user
      /;

    for my $segment ( @segments_for_invalidation )
    {

        my $r = 0;
        if ( any { $_ eq $segment } @url_segments )
        {
            return 1;
        }
    }

    return 0;
}

# guess the date for the story by cycling through the $_date_guess_functions one at a time.
# returns MediaWords::CM::GuessDate::Result object
sub guess_date_impl
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

    my $story_timestamp = $story->{ publish_date } ? _make_unix_timestamp( $story->{ publish_date } ) : undef;

    for my $date_guess_function ( @{ $_date_guess_functions } )
    {
        if ( my $timestamp = _make_unix_timestamp( $date_guess_function->{ function }->( $story, $html, $html_tree ) ) )
        {
            if (   $story_timestamp
                && $use_threshold
                && ( ( $timestamp - $story_timestamp ) > ( DATE_GUESS_THRESHOLD * 86400 ) ) )
            {
                next;
            }

            # Found
            $result->{ result }       = MediaWords::CM::GuessDate::Result::FOUND;
            $result->{ guess_method } = $date_guess_function->{ name };
            $result->{ timestamp }    = $timestamp;
            $result->{ date }         = MediaWords::Util::SQL::get_sql_date_from_epoch( $timestamp );
            return $result;
        }
    }

    if ( $story_timestamp )
    {

        # print STDERR "SOURCE LINK\n";
        $result->{ result }       = MediaWords::CM::GuessDate::Result::FOUND;
        $result->{ guess_method } = 'source_link';
        $result->{ timestamp }    = $story_timestamp;
        $result->{ date }         = MediaWords::Util::SQL::get_sql_date_from_epoch( $story_timestamp );
        return $result;
    }

    # Not found
    $result->{ result } = MediaWords::CM::GuessDate::Result::NOT_FOUND;
    return $result;
}

# guess the date for the story by cycling through the $_date_guess_functions one at a time.
# returns MediaWords::CM::GuessDate::Result object
sub guess_date($$$;$)
{

    # we have to wrap everything in an eval, because the xml treebuilder stuff is liable to dying
    # in unpredictable ways
    my $r;
    eval { $r = guess_date_impl( @_ ) };

    return $r if ( $r );

    $r = MediaWords::CM::GuessDate::Result->new();
    $r->{ result } = MediaWords::CM::GuessDate::Result::INAPPLICABLE;
    return $r;
}

1;
