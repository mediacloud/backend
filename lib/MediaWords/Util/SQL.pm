package MediaWords::Util::SQL;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

# misc utility functions for sql

use strict;

use DateTime;
use DateTime::Format::Pg;
use Time::Local;

my $_local_tz = DateTime::TimeZone->new( name => 'local' );

# given a ref to a list of ids, return a list suitable
# for including in a query as an in list, eg:
# 1,2,3,4
sub get_ids_in_list
{
    my ( $list ) = @_;

    if ( grep( /[^0-9]/, @{ $list } ) )
    {
        die( "non-number list id list: " . join( ', ', @{ $list } ) );
    }

    return join( ',', @{ $list } );
}

sub get_sql_date_from_epoch
{
    my ( $epoch ) = @_;

    my $dt = DateTime->from_epoch( epoch => $epoch );
    $dt->set_time_zone( $_local_tz );

    my $date = $dt->datetime;

    $date =~ s/(\d)T(\d)/$1 $2/;

    return $date;
}

sub sql_now
{
    return get_sql_date_from_epoch( time() );
}

# given a date in the sql format 'YYYY-MM-DD', return the epoch time
sub get_epoch_from_sql_date
{
    my ( $date ) = @_;

    my $dt = DateTime::Format::Pg->parse_datetime( $date );
    $dt->set_time_zone( $_local_tz );

    return $dt->epoch;
}

# given a date in the sql format 'YYYY-MM-DD', increment it by $days days
sub increment_day
{
    my ( $date, $days ) = @_;

    return $date if ( defined( $days ) && ( $days == 0 ) );

    $days = 1 if ( !defined( $days ) );

    my $epoch_date = get_epoch_from_sql_date( $date ) + ( ( ( $days * 24 ) + 12 ) * 60 * 60 );

    my ( undef, undef, undef, $day, $month, $year ) = localtime( $epoch_date );

    return sprintf( '%04d-%02d-%02d', $year + 1900, $month + 1, $day );
}

# given a date in sql format 'YYYY-MM-DD', increment it to the current or next monday
sub increment_to_monday
{
    my ( $date ) = @_;

    while ( ( localtime( get_epoch_from_sql_date( $date ) ) )[ 6 ] != 1 )
    {
        $date = increment_day( $date, 1 );
    }

    return $date;
}

# in many cases, querying a date field with an in() clause with individual dates
# is much faster than using date >= $start_date and < $end_date
sub get_days_clause
{
    my ( $start_date, $end_date ) = @_;

    my $dates = [];
    for ( my $d = $start_date ; $d le $end_date ; $d = MediaWords::Util::SQL::increment_day( $d, 1 ) )
    {
        push( @{ $dates }, $d );
    }

    return "in ( " . join( ',', map { "'$_'" } @{ $dates } ) . " )";
}

1;
