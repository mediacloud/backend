package MediaWords::Util::DateTime;

#
# Date- and time-related helpers
#

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

our @ISA    = qw(Exporter);
our @EXPORT = qw(gmt_datetime_from_timestamp gmt_date_string_from_timestamp);

use DateTime;

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

1;
