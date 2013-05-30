package MediaWords::CM::GuessDate;

# guess the date of a spidered story using a combination of the story url, html, and
# a first guess date

# FIXME EST to GMT

use strict;

use DateTime;
use Date::Parse;
use HTML::TreeBuilder::LibXML;
use LWP::Simple;

use MediaWords::CommonLibs;
use MediaWords::CM::GuessDate;
use MediaWords::DB;

# threshhold of number of days a guess date can be off from the existing
# story date without dropping the guess
my $_date_guess_threshhold = 14;

# only use the date from these guessing functions if the date is within $_date_guess_threshhold days
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
        name     => 'guess_by_http_last_modified',
        function => \&_guess_by_http_last_modified
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

# look into HTTP Last-Modified header
sub _guess_by_http_last_modified
{
    my ( $story, $html, $html_tree ) = @_;

    my $url = $story->{ url };

    my ( $content_type, $doc_length, $mod_time, $expires, $server );

    # Don't test IANA example domains
    my $host = URI->new( $url )->host;
    if ( $host =~ /example\.(com|net|org)$/i )
    {
        return undef;
    }

    if ( ( $content_type, $doc_length, $mod_time, $expires, $server ) = head( $url ) )
    {
        if ( $mod_time )
        {

            # Don't trust modification dates newer than one day
            # (because that modification date might be today's timestamp)
            if ( time() - $mod_time > ( 60 * 60 * 24 ) )
            {
                return $mod_time;
            }

        }
    }

    # Fallback
    return undef;
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

# look for any month name followed by something that looks like a date
sub _guess_by_date_text
{
    my ( $story, $html, $html_tree ) = @_;

    my $month_names   = [ qw/january february march april may june july august september october november december/ ];
    my $weekday_names = [ qw/monday tuesday wednesday thursday friday saturday sunday/ ];

    push( @{ $month_names },   map { substr( $_, 0, 3 ) } @{ $month_names } );
    push( @{ $weekday_names }, map { substr( $_, 0, 3 ) } @{ $weekday_names } );

    my $month_names_pattern   = join( '|', @{ $month_names } );
    my $weekday_names_pattern = join( '|', @{ $weekday_names } );

    # January 17, 2012 2:31 PM EST
    if (
        $html =~ /(
            (?:$month_names_pattern)    # January, February, ..., Jan, Feb, ...
            \s*
            \d\d?(?:st|th)?             # 1, 2, 3, ..., 31 (optional '-st', '-th' suffix)
            (?:,|\s+at)?                # optional comma or "at"
            \s+
            20\d\d                      # year
            (
                ?:,?                    # optional comma
                \s*
                \d\d?\:\d\d             # HH:mm
                \s*
                ([AP]M)?                # optional AM or PM
                (?:\s+\w\wT)?           # optional timezone
            )?
            )/ix
      )
    {
        my $date_string = $1;

        return $date_string;
    }

    # Wednesday, 29 August 2012 03:55
    if (
        $html =~ /(
        (?:$weekday_names_pattern)      # Monday, Tuesday, ..., Mon, Tue, ...
        \s*?,\s*?                       # comma
        \d\d?(?:st|th)?                 # 1, 2, 3, ..., 31 (optional '-st', '-th' suffix)
        \s+
        (?:$month_names_pattern)        # January, February, ..., Jan, Feb, ...
        \s+
        20\d\d                          # year
        (
            ?:,?                        # optional comma
            \s*
            \d\d?\:\d\d                 # HH:mm
            \s*
            ([AP]M)?                    # optional AM or PM
            (?:\s+\w\wT)?               # optional timezone
        )?
        )/ix
      )
    {
        my $date_string = $1;
        return $date_string;
    }
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

# guess the date for the story by cycling through the $_date_guess_functions one at a time.
# return the date as UNIX timestamp.
sub guess_timestamp($$$;$)
{
    my ( $db, $story, $html, $use_threshold ) = @_;

    my $html_tree = _get_html_tree( $html );

    my $story_timestamp = _make_unix_timestamp( $story->{ publish_date } );

    for my $date_guess_function ( @{ $_date_guess_functions } )
    {
        if ( my $timestamp = _make_unix_timestamp( $date_guess_function->{ function }->( $story, $html, $html_tree ) ) )
        {
            if ( $use_threshold && ( abs( $timestamp - $story_timestamp ) < ( $_date_guess_threshhold * 86400 ) ) )
            {
                next;
            }
            return wantarray ? ( $date_guess_function->{ name }, $timestamp ) : $timestamp;
        }
    }

    return undef;
}

# guess the date for the story by cycling through the $_date_guess_functions one at a time.
# return the date as ISO-8601 string in GMT timezone (e.g. '2012-01-17T17:00:00')
sub guess_date($$$;$)
{
    my ( $db, $story, $html, $use_threshold ) = @_;

    my ( $name, $timestamp ) = guess_timestamp( $db, $story, $html, $use_threshold );
    unless ( defined( $timestamp ) )
    {
        return undef;
    }

    my $date = DateTime->from_epoch( epoch => $timestamp )->datetime;
    return wantarray ? ( $name, $date ) : $date;
}

1;
