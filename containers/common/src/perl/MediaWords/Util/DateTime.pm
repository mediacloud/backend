package MediaWords::Util::DateTime;

#
# Date- and time-related helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use DateTime;

use Date::Parse;
use Time::Local;

# Cached because slow
my $_local_tz = undef;

# Return system timezone
sub local_timezone
{
    unless ( $_local_tz )
    {
        $_local_tz = DateTime::TimeZone->new( name => 'local' );
        if ( $_local_tz->is_utc )
        {
            # Ubuntu 16.04 doesn't set timezone properly
            ERROR "Local timezone is set to UTC, you probably need to edit /etc/timezone";
        }
    }

    return $_local_tz;
}

# Using UNIX timestamp as a parameter, return a DateTime object using GMT
# timezone
sub gmt_datetime_from_timestamp($)
{
    my $timestamp = shift;

    return DateTime->from_epoch( epoch => $timestamp, time_zone => 'Etc/GMT' );
}

# Using UNIX timestamp as a parameter, return a string date (in ISO8601 format,
# e.g. "2014-09-03T15:44:23") using GMT timezone
sub gmt_date_string_from_timestamp($)
{
    my $timestamp = shift;

    return gmt_datetime_from_timestamp( $timestamp )->datetime();
}

# Proxy to Date::Parse's str2time() which treats "61" as 2061, not 1961
sub str2time_21st_century($;$)
{
    my ( $date, $timezone ) = @_;

    $date =~ s/^\s+|\s+$//g;

    my $timestamp;

    # str2time() doesn't handle YYYY-mm-dd dates correctly
    if ( $date =~ m/^([12]\d\d\d)-(\d\d)-(\d\d)$/ )
    {
        my $year  = $1;
        my $month = $2;
        my $day   = $3;

        $timestamp = timelocal( 0, 0, 0, $day, $month - 1, $year );
    }
    else
    {
        $timestamp = str2time( $date, $timezone );
    }

    return $timestamp;
}

1;
