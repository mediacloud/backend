package MediaWords::Util::DateTime;

#
# Date- and time-related helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use DateTime;
use MediaWords::Util::DateParse;

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
            say STDERR "Local timezone is set to UTC, you probably need to edit /etc/timezone";
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
sub str2time_21st_century
{
    return MediaWords::Util::DateParse::str2time( @_ );
}

# Proxy to Date::Parse's strptime() which treats "61" as 2061, not 1961
sub strptime_21st_century
{
    return MediaWords::Util::DateParse::strptime( @_ );
}

1;
