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
#      # Will use locally cached copies of stories
#      ./script/run_with_carton.sh ./script/evaluate_date_guessing.pl t/data/cm_date_guessing_sample.csv t/data/cm_date_guessing_sample/ 2>&1 | tee date_guessing.log
#  or
#      # Will download stories from the web
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

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::CM::GuessDate;
use MediaWords::CM::GuessDate::Result;
use MediaWords::DBI::Stories;
use Date::Parse;
use POSIX;
use LWP::Simple;
use Text::CSV;
use List::Util qw(max min);
use File::Slurp;

sub _timestamp_to_date($)
{
    my $timestamp = shift;
    return DateTime->from_epoch( epoch => $timestamp )->datetime;
}

sub get_non_russian_rows ($$)
{
    my ( $db, $rows ) = @_;

    my $stories_ids_list = join( ',', map { $_->{ stories_id } } @{ $rows } );

    my $russian_stories = $db->query( <<END )->hashes;
select s.stories_id
    from stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id )
        join controversies c on ( cs.controversies_id = c.controversies_id )
    where
        lower( c.name ) like '%russia%' and
        s.stories_id in ( $stories_ids_list )
END

    my $non_controversy_stories = $db->query( <<END )->hashes;
select s.stories_id
    from stories s
        left join controversy_stories cs on ( s.stories_id = cs.stories_id )
    where
        s.stories_id in ( $stories_ids_list ) and
        cs.stories_id is null
END

    my $skip_story_lookup = {};
    map { $skip_story_lookup->{ $_->{ stories_id } } = 1 } @{ $russian_stories };
    map { $skip_story_lookup->{ $_->{ stories_id } } = 1 } @{ $non_controversy_stories };

    my $nrr = [];
    for my $row ( @{ $rows } )
    {
        if ( $skip_story_lookup->{ $row->{ stories_id } } )
        {

            # print STDERR "skip story: $row->{ url }\n";
        }
        else
        {
            push( @{ $nrr }, $row );
        }
    }

    print STDERR "skip stories: keep " . scalar( @{ $nrr } ) . " / " . scalar( @{ $rows } ) . " stories\n";

    return $nrr;
}

sub main()
{
    unless ( $ARGV[ 0 ] )
    {
        die "Usage: $0 urls_and_manual_dates.csv [input_folder/]\n";
    }

    my Readonly $urls_and_manual_dates_file = $ARGV[ 0 ];
    unless ( -e $urls_and_manual_dates_file )
    {
        die "File '$urls_and_manual_dates_file' does not exist.\n";
    }
    my Readonly $output_folder = $ARGV[ 1 ];
    if ( $output_folder )
    {
        unless ( -d $output_folder )
        {
            die "Output folder '$output_folder' does not exist.\n";
        }
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

    my $stories_dump = '';

    my $file = $ARGV[ 0 ];
    open( FILE, $file ) || die( "Unable to open file '$file': $!" );

    while ( my $line = <FILE> )
    {
        $stories_dump .= $line;
    }
    close FILE;

    my $csv = Text::CSV->new( { binary => 1 } ) or die "Cannot use CSV: " . Text::CSV->error_diag();
    open my $fh, "<:encoding(utf8)", $ARGV[ 0 ] or die $ARGV[ 0 ] . ": $!";
    $csv->column_names( $csv->getline( $fh ) );
    my $rows = [];
    while ( my $row = $csv->getline_hr( $fh ) )
    {
        push( @{ $rows }, $row );
    }

    my $non_russian_rows = get_non_russian_rows( $db, $rows );

    for my $row ( @{ $non_russian_rows } )
    {
        my $stories_id = $row->{ stories_id };
        my $url        = $row->{ url };

        my $source_story = $db->query( <<END, $row->{ stories_id } )->hash;
select s.* 
    from controversy_links cl 
        join stories s on ( cl.stories_id = s.stories_id )
    where 
        ref_stories_id = ? 
    order by controversy_links_id asc
END

        # Reformat date
        my $actual_date   = $row->{ actual_publication_date };
        my $actual_result = MediaWords::CM::GuessDate::Result->new();
        if ( $actual_date eq 'not found' )
        {
            $actual_result->{ result } = $MediaWords::CM::GuessDate::Result::NOT_FOUND;
        }
        elsif ( $actual_date eq 'unavailable' or $actual_date eq 'inapplicable' )
        {

            # Treat HTTP 404 errors as "inapplicable"
            $actual_result->{ result } = $MediaWords::CM::GuessDate::Result::INAPPLICABLE;
        }
        else
        {
            $actual_result->{ result }    = $MediaWords::CM::GuessDate::Result::FOUND;
            $actual_result->{ timestamp } = Date::Parse::str2time( $actual_date, 'GMT' );
            $actual_result->{ date }      = _timestamp_to_date( $actual_result->{ timestamp } );  # for display purposes only
        }

        say STDERR "Dating story $stories_id: $url...";
        say STDERR "\tActual date:  " . ( $actual_result->{ date } || $actual_result->{ result } ) . " (" .
          ( $actual_result->{ timestamp } || 'undef' ) . ")";

        # Try to guess a date
        my $html;
        if ( $output_folder )
        {
            $html = read_file( $output_folder . '/' . $stories_id );
        }
        else
        {
            $html = get( $url );
        }
        my $story = { url => $url, publish_date => $source_story->{ publish_date } };
        my $guessed_result = MediaWords::CM::GuessDate::guess_date( $db, $story, $html, 1 );

        # Old API (e.g. "013-06-17T05:00:00")?
        my $do_not_differentiate_between_not_found_and_inapplicable = 0;
        unless ( ref( $guessed_result ) )
        {
            my $guessed_timestamp = Date::Parse::str2time( $guessed_result, 'GMT' );
            $guessed_result = MediaWords::CM::GuessDate::Result->new();
            if ( $guessed_timestamp )
            {
                $guessed_result->{ result }    = $MediaWords::CM::GuessDate::Result::FOUND;
                $guessed_result->{ timestamp } = $guessed_timestamp;
                $guessed_result->{ date }      = _timestamp_to_date( $guessed_timestamp );    # for display purposes only
            }
            else
            {
                $guessed_result->{ result } = $MediaWords::CM::GuessDate::Result::NOT_FOUND;
            }
        }
        say STDERR "\tGuessed date: " . ( $guessed_result->{ date } || $guessed_result->{ result } ) .
          " (" . ( $guessed_result->{ timestamp } || 'undef' ) . "), guessed with '" .
          ( $guessed_result->{ guess_method } || '-' ) . "'";

        # Write down numbers
        ++$guesses->{ _total };
        if (    $actual_result->{ result } eq $MediaWords::CM::GuessDate::Result::FOUND
            and $guessed_result->{ result } eq $MediaWords::CM::GuessDate::Result::FOUND )
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
                    say STDERR "\tMatch within [0; 24] hours";
                    ++$guesses->{ incorrect }->{ dateable }->{ up_to_1_day };

                }
                elsif ( $difference >= 60 * 60 * 24 and $difference < 60 * 60 * 24 * 3 )
                {
                    say STDERR "\tMatch within [24; 72] hours";
                    ++$guesses->{ incorrect }->{ dateable }->{ from_1_day_to_3_days };

                }
                elsif ( $difference >= 60 * 60 * 24 * 3 and $difference < 60 * 60 * 24 * 7 )
                {
                    say STDERR "\tMatch within [72; 168] hours";
                    ++$guesses->{ incorrect }->{ dateable }->{ from_3_days_to_7_days };

                }
                else
                {
                    say STDERR "\tMatch within [168; inf] hours";
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

                if ( $actual_result->{ result } eq $MediaWords::CM::GuessDate::Result::NOT_FOUND )
                {
                    ++$guesses->{ correct }->{ _total };
                    ++$guesses->{ correct }->{ undateable }->{ _total };
                    ++$guesses->{ correct }->{ undateable }->{ not_found };

                }
                elsif ( $actual_result->{ result } eq $MediaWords::CM::GuessDate::Result::INAPPLICABLE )
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
                  $actual_result->{ result } . "; got: " . $guessed_result->{ result } . ")";

                ++$guesses->{ incorrect }->{ _total };
                ++$guesses->{ incorrect }->{ undateable }->{ _total };

                if ( $actual_result->{ result } eq $MediaWords::CM::GuessDate::Result::FOUND )
                {

                    if ( $guessed_result->{ result } eq $MediaWords::CM::GuessDate::Result::NOT_FOUND )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_date }->{ got_not_found };
                    }
                    elsif ( $guessed_result->{ result } eq $MediaWords::CM::GuessDate::Result::INAPPLICABLE )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_date }->{ got_inapplicable };
                    }
                    else
                    {
                        die "Not configured for result " . $guessed_result->{ result };
                    }

                }
                elsif ( $actual_result->{ result } eq $MediaWords::CM::GuessDate::Result::NOT_FOUND )
                {

                    if ( $guessed_result->{ result } eq $MediaWords::CM::GuessDate::Result::FOUND )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_not_found }->{ got_date };
                    }
                    elsif ( $guessed_result->{ result } eq $MediaWords::CM::GuessDate::Result::INAPPLICABLE )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_not_found }->{ got_inapplicable };
                    }
                    else
                    {
                        die "Not configured for result " . $guessed_result->{ result };
                    }

                }
                elsif ( $actual_result->{ result } eq $MediaWords::CM::GuessDate::Result::INAPPLICABLE )
                {

                    if ( $guessed_result->{ result } eq $MediaWords::CM::GuessDate::Result::FOUND )
                    {
                        ++$guesses->{ incorrect }->{ undateable }->{ expected_inapplicable }->{ got_date };
                    }
                    elsif ( $guessed_result->{ result } eq $MediaWords::CM::GuessDate::Result::NOT_FOUND )
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

    # Pretty-print the results
    say STDERR <<"EOF";

TOTAL guesses: $guesses->{ _total }, among those:

    CORRECT guesses: $guesses->{ correct }->{ _total }, among those:

        CORRECT guesses where both sides are DATEABLE: $guesses->{ correct }->{ dateable }->{ _total }, among those:
            CORRECT guesses where both sides are DATEABLE and the date is EXACTLY THE SAME: $guesses->{ correct }->{ dateable }->{ exact }
            CORRECT guesses where both sides are DATEABLE and the date is WITHIN THE SAME CALENDAR DAY: $guesses->{ correct }->{ dateable }->{ same_day }

        CORRECT guesses where both sides are UNDATEABLE: $guesses->{ correct }->{ undateable }->{ _total }, among those:
            CORRECT guesses where both sides are UNDATEABLE and the DATE WAS NOT FOUND: $guesses->{ correct }->{ undateable }->{ not_found }
            CORRECT guesses where both sides are UNDATEABLE and the DATING IS INAPPLICABLE: $guesses->{ correct }->{ undateable }->{ inapplicable }

    INCORRECT guesses: $guesses->{ incorrect }->{ _total }, among those:

        INCORRECT guesses where BOTH SIDES ARE DATEABLE: $guesses->{ incorrect }->{ dateable }->{ _total }, among those:
            INCORRECT guesses where BOTH SIDES ARE DATEABLE and the difference is UP TO 1 DAY ((0; 24) hours): $guesses->{ incorrect }->{ dateable }->{ up_to_1_day }
            INCORRECT guesses where BOTH SIDES ARE DATEABLE and the difference is FROM 1 DAY TO 3 DAYS ([24; 72) hours): $guesses->{ incorrect }->{ dateable }->{ from_1_day_to_3_days }
            INCORRECT guesses where BOTH SIDES ARE DATEABLE and the difference is FROM 3 DAYS TO 7 DAYS ([72; 168) hours): $guesses->{ incorrect }->{ dateable }->{ from_3_days_to_7_days }
            INCORRECT guesses where BOTH SIDES ARE DATEABLE and the difference is 7 DAYS OR MORE ([168; inf) hours): $guesses->{ incorrect }->{ dateable }->{ more_than_7_days }

        INCORRECT guesses where ONE SIDE IS NOT DATEABLE: $guesses->{ incorrect }->{ undateable }->{ _total }, among those:

            INCORRECT guesses where one side IS NOT DATEABLE and the expected result is A DATE:
                INCORRECT guesses where one side IS NOT DATEABLE and the expected result is A DATE but the guessed result is "DATE NOT FOUND": $guesses->{ incorrect }->{ undateable }->{ expected_date }->{ got_not_found }
                INCORRECT guesses where one side IS NOT DATEABLE and the expected result is A DATE but the guessed result is "DATING IS INAPPLICABLE": $guesses->{ incorrect }->{ undateable }->{ expected_date }->{ got_inapplicable }

            INCORRECT guesses where one side IS NOT DATEABLE and the expected result is "DATE NOT FOUND":
                INCORRECT guesses where one side IS NOT DATEABLE and the expected result is "DATE NOT FOUND" but the guessed result is A DATE: $guesses->{ incorrect }->{ undateable }->{ expected_not_found }->{ got_date }
                INCORRECT guesses where one side IS NOT DATEABLE and the expected result is "DATE NOT FOUND" but the guessed result is "DATING IS INAPPLICABLE": $guesses->{ incorrect }->{ undateable }->{ expected_not_found }->{ got_inapplicable }
                
            INCORRECT guesses where one side IS NOT DATEABLE and the expected result is "DATING IS INAPPLICABLE":
                INCORRECT guesses where one side IS NOT DATEABLE and the expected result is "DATING IS INAPPLICABLE" but the guessed result is A DATE: $guesses->{ incorrect }->{ undateable }->{ expected_inapplicable }->{ got_date }
                INCORRECT guesses where one side IS NOT DATEABLE and the expected result is "DATING IS INAPPLICABLE" but the guessed result is "DATE NOT FOUND": $guesses->{ incorrect }->{ undateable }->{ expected_inapplicable }->{ got_not_found }

EOF

}

main();
