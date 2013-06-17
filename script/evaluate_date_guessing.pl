#!/usr/bin/env perl
#
# Evaluate date guessing algorithm
#
# Params:
# * CSV file with the the columns which include at least:
#     * "stories_id" -- story's ID
#     * "url" -- story's URL
#     * "actual_publication_date" -- manually dated story publication date (in format readable by Date::Parse::str2time())
#

use strict;
use warnings;

use utf8;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::CM::GuessDate;
use MediaWords::CM::GuessDate::Result;
use Date::Parse;
use POSIX;
use LWP::Simple;
use Text::CSV;
use List::Util qw(max min);

sub _timestamp_to_date($)
{
    my $timestamp = shift;
    return DateTime->from_epoch( epoch => $timestamp )->datetime;
}

sub main()
{
    unless ( $ARGV[ 0 ] )
    {
        die "Usage: $0 urls_and_manual_dates.csv\n";
    }

    my $db = MediaWords::DB::connect_to_db();

    # Counts
    my $guesses_total                 = 0;
    my $guesses_correct_exact         = 0;
    my $guesses_correct_sameday       = 0;    # same calendar day
    my $guesses_correct_within24hours = 0;    # +/- 24 hours

    my $csv = Text::CSV->new( { binary => 1 } ) or die "Cannot use CSV: " . Text::CSV->error_diag();
    open my $fh, "<:encoding(utf8)", $ARGV[ 0 ] or die $ARGV[ 0 ] . ": $!";
    $csv->column_names( $csv->getline( $fh ) );
    while ( my $row = $csv->getline_hr( $fh ) )
    {

        my $stories_id = $row->{ stories_id };
        my $url        = $row->{ url };

        # Reformat date
        my $actual_date   = $row->{ actual_publication_date };
        my $actual_result = MediaWords::CM::GuessDate::Result->new();
        if ( $actual_date eq 'not found' )
        {
            $actual_result->{ result } = MediaWords::CM::GuessDate::Result::NOT_FOUND;
        }
        elsif ( $actual_date eq 'unavailable' or $actual_date eq 'inapplicable' )
        {
            # Treat HTTP 404 errors as "inapplicable"
            $actual_result->{ result } = MediaWords::CM::GuessDate::Result::INAPPLICABLE;
        }
        else
        {
            $actual_result->{ result }    = MediaWords::CM::GuessDate::Result::FOUND;
            $actual_result->{ timestamp } = Date::Parse::str2time( $actual_date, 'GMT' );
            $actual_result->{ date }      = _timestamp_to_date( $actual_result->{ timestamp } );  # for display purposes only
        }

        say STDERR "Dating story $stories_id: $url...";
        say STDERR "\tActual date:  " . ( $actual_result->{ date } || $actual_result->{ result } ) . " (" .
          ( $actual_result->{ timestamp } || 'undef' ) . ")";
        my $html           = get( $url );
        my $story          = { url => $url };
        my $guessed_result = MediaWords::CM::GuessDate::guess_date( $db, $story, $html );
        say STDERR "\tGuessed date: " . ( $guessed_result->{ date } || $guessed_result->{ result } ) .
          " (" . ( $guessed_result->{ timestamp } || 'undef' ) . "), guessed with '" .
          ( $guessed_result->{ guess_method } || '-' ) . "'";

        ++$guesses_total;
        if (    $actual_result->{ result } eq MediaWords::CM::GuessDate::Result::FOUND
            and $guessed_result->{ result } eq MediaWords::CM::GuessDate::Result::FOUND )
        {

            if ( $actual_result->{ timestamp } == $guessed_result->{ timestamp } )
            {
                say STDERR "\tExact match";
                ++$guesses_correct_exact;
            }

            elsif ( strftime( "%a %b %e", gmtime( $actual_result->{ timestamp } ) ) eq
                strftime( "%a %b %e", gmtime( $guessed_result->{ timestamp } ) ) )
            {
                say STDERR "\tMatch within the same calendar day";
                ++$guesses_correct_sameday;
            }

            elsif ( max( $actual_result->{ timestamp }, $guessed_result->{ timestamp } ) -
                min( $actual_result->{ timestamp }, $guessed_result->{ timestamp } ) < 60 * 60 * 24 )
            {
                say STDERR "\tMatch within 24 hours";
                ++$guesses_correct_within24hours;

            }

        }
        else
        {

            # If both are undefined, that might be a correct match too
            if ( $actual_result->{ result } eq $guessed_result->{ result } )
            {
                say STDERR "\tExact match (both '" . $actual_result->{ result } . "')";
                ++$guesses_correct_exact;
            }

        }

        say STDERR "";
    }

    $csv->eof or $csv->error_diag();
    close $fh;

    say STDERR "Total dates guessed: $guesses_total";
    say STDERR "Correct guesses - exact: $guesses_correct_exact";
    say STDERR "Correct guesses - same calendar day: $guesses_correct_sameday";
    say STDERR "Correct guesses - within 24 hours: $guesses_correct_within24hours";
}

main();
