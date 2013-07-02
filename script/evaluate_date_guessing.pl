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
# Example:
#      ./script/run_with_carton.sh ./script/evaluate_date_guessing.pl t/data/cm_date_guessing_sample.csv 2>&1 | tee date_guessing.log
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
    my $guesses = {
        _total  => 0,
        correct => {
            _total   => 0,
            dateable => {    # both stories are dateable
                _total   => 0,    # either exact match or within the same calendar day
                exact    => 0,    # exact match
                same_day => 0,    # within the same calendar day
            },
            undateable => {
                _total       => 0,
                not_found    => 0,    # date not found on both stories
                inapplicable => 0,    # date not applicable to both stories
            },
        },
        incorrect => {
            _total   => 0,            # any kind of incorrect matches
            dateable => {             # when both stories are dateable
                _total                => 0,
                up_to_1_day           => 0,    # (0; 24) hours
                from_1_day_to_3_days  => 0,    # [24; 72) hours
                from_3_days_to_7_days => 0,    # [72; 168) hours
                more_than_7_days      => 0,    # [168; inf) hours
            },
            undateable => {                    # when one of the stories is undateable
                _total        => 0,
                expected_date => {
                    got_not_found    => 0,
                    got_inapplicable => 0,
                },
                expected_not_found => {
                    got_date         => 0,
                    got_inapplicable => 0,
                },
                expected_inapplicable => {
                    got_date      => 0,
                    got_not_found => 0,
                },
            },
        },
    };

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

        # Try to guess a date
        my $html           = get( $url );
        my $story          = { url => $url };
        my $guessed_result = MediaWords::CM::GuessDate::guess_date( $db, $story, $html );

        # Old API (e.g. "013-06-17T05:00:00")?
        my $do_not_differentiate_between_not_found_and_inapplicable = 0;
        unless ( ref( $guessed_result ) )
        {
            my $guessed_timestamp = Date::Parse::str2time( $guessed_result, 'GMT' );
            $guessed_result = MediaWords::CM::GuessDate::Result->new();
            if ( $guessed_timestamp )
            {
                $guessed_result->{ result }    = MediaWords::CM::GuessDate::Result::FOUND;
                $guessed_result->{ timestamp } = $guessed_timestamp;
                $guessed_result->{ date }      = _timestamp_to_date( $guessed_timestamp );    # for display purposes only
            }
            else
            {
                $guessed_result->{ result } = MediaWords::CM::GuessDate::Result::NOT_FOUND;
            }
        }
        say STDERR "\tGuessed date: " . ( $guessed_result->{ date } || $guessed_result->{ result } ) .
          " (" . ( $guessed_result->{ timestamp } || 'undef' ) . "), guessed with '" .
          ( $guessed_result->{ guess_method } || '-' ) . "'";

        # Write down numbers
        ++$guesses->{ _total };
        if (    $actual_result->{ result } eq MediaWords::CM::GuessDate::Result::FOUND
            and $guessed_result->{ result } eq MediaWords::CM::GuessDate::Result::FOUND )
        {
            # Both are dateable

            if ( $actual_result->{ timestamp } == $guessed_result->{ timestamp } )
            {
                say STDERR "\tExact match";
                ++$guesses->{ correct }->{ _total };
                ++$guesses->{ correct }->{ dateable }->{ _total };
                ++$guesses->{ correct }->{ dateable }->{ exact };
            }

            elsif ( strftime( "%a %b %e", gmtime( $actual_result->{ timestamp } ) ) eq
                strftime( "%a %b %e", gmtime( $guessed_result->{ timestamp } ) ) )
            {
                say STDERR "\tMatch within the same calendar day";
                ++$guesses->{ correct }->{ _total };
                ++$guesses->{ correct }->{ dateable }->{ _total };
                ++$guesses->{ correct }->{ dateable }->{ same_day };

            }
            else
            {

                ++$guesses->{ incorrect }->{ _total };
                ++$guesses->{ incorrect }->{ dateable }->{ _total };

                my $difference =
                  max( $actual_result->{ timestamp }, $guessed_result->{ timestamp } ) -
                  min( $actual_result->{ timestamp }, $guessed_result->{ timestamp } );

                if ( $difference < 60 * 60 * 24 )
                {
                    say STDERR "\tMatch within (0; 24) hours";
                    ++$guesses->{ incorrect }->{ dateable }->{ up_to_1_day };

                }
                elsif ( $difference >= 60 * 60 * 24 and $difference < 60 * 60 * 24 * 3 )
                {
                    say STDERR "\tMatch within [24; 72) hours";
                    ++$guesses->{ incorrect }->{ dateable }->{ from_1_day_to_3_days };

                }
                elsif ( $difference >= 60 * 60 * 24 * 3 and $difference < 60 * 60 * 24 * 7 )
                {
                    say STDERR "\tMatch within [72; 168) hours";
                    ++$guesses->{ incorrect }->{ dateable }->{ from_3_days_to_7_days };

                }
                else
                {
                    say STDERR "\tMatch within [168; inf) hours";
                    ++$guesses->{ incorrect }->{ dateable }->{ more_than_7_days };

                }

            }

        }
        else
        {
            # One of the stories is undateable (either date not found or dating is inapplicable)

            if ( $actual_result->{ result } eq $guessed_result->{ result } )
            {
                say STDERR "\tExact match (both '" . $actual_result->{ result } . "')";

                if ( $actual_result->{ result } eq MediaWords::CM::GuessDate::Result::NOT_FOUND )
                {
                    ++$guesses->{ correct }->{ _total };
                    ++$guesses->{ correct }->{ undateable }->{ _total };
                    ++$guesses->{ correct }->{ undateable }->{ not_found };

                }
                elsif ( $actual_result->{ result } eq MediaWords::CM::GuessDate::Result::INAPPLICABLE )
                {
                    ++$guesses->{ correct }->{ _total };
                    ++$guesses->{ correct }->{ undateable }->{ _total };
                    ++$guesses->{ correct }->{ undateable }->{ inapplicable };

                }
                else
                {
                    die "Not configured for result " . $actual_result->{ result };

                }

            }
            else
            {

                say STDERR "\tMismatch (expected: " .
                  $actual_result->{ result } . "; got: " . $guessed_result->{ result } . " )";

                ++$guesses->{ incorrect }->{ _total };
                ++$guesses->{ incorrect }->{ undateable }->{ _total };

                if ( $actual_result->{ result } eq MediaWords::CM::GuessDate::Result::FOUND )
                {

                    if ( $guessed_result->{ result } eq MediaWords::CM::GuessDate::Result::NOT_FOUND )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_date }->{ got_not_found };
                    }
                    elsif ( $guessed_result->{ result } eq MediaWords::CM::GuessDate::Result::INAPPLICABLE )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_date }->{ got_inapplicable };
                    }
                    else
                    {
                        die "Not configured for result " . $guessed_result->{ result };
                    }

                }
                elsif ( $actual_result->{ result } eq MediaWords::CM::GuessDate::Result::NOT_FOUND )
                {

                    if ( $guessed_result->{ result } eq MediaWords::CM::GuessDate::Result::FOUND )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_not_found }->{ got_date };
                    }
                    elsif ( $guessed_result->{ result } eq MediaWords::CM::GuessDate::Result::INAPPLICABLE )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_not_found }->{ got_inapplicable };
                    }
                    else
                    {
                        die "Not configured for result " . $guessed_result->{ result };
                    }

                }
                elsif ( $actual_result->{ result } eq MediaWords::CM::GuessDate::Result::INAPPLICABLE )
                {

                    if ( $guessed_result->{ result } eq MediaWords::CM::GuessDate::Result::FOUND )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_inapplicable }->{ got_date };
                    }
                    elsif ( $guessed_result->{ result } eq MediaWords::CM::GuessDate::Result::NOT_FOUND )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_inapplicable }->{ got_not_found };
                    }
                    else
                    {
                        die "Not configured for result " . $guessed_result->{ result };
                    }

                }
                else
                {
                    die "Not configured for result " . $actual_result->{ result };

                }

            }

        }

        say STDERR "";
    }

    $csv->eof or $csv->error_diag();
    close $fh;

    say STDERR Dumper( $guesses );
}

main();
