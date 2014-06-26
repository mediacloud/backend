#!/usr/bin/env perl

# accept a csv with a stories_id and a publish_date field.  change any dates
# that are different in the csv than in the existing story.

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Date::Parse;
use DateTime;
use Getopt::Long;
use Text::CSV_XS;

use MediaWords::CM::GuessDate;
use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Util::Tags;

# hash of fixed stories to avoid resetting a story once it has been fixed
my $_fixed_stories_map = {};

# if debug is set by the --debug option, do not run sql commands
my $_debug;

# parse the csv file and return a hash with a stories_id, publish_date, and option dateable field
sub get_csv_dates
{
    my ( $file ) = @_;

    my $csv = Text::CSV_XS->new( { binary => 1 } ) || die "error using CSV_XS: " . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(utf8)", $file || die "Unable to open file $file: $!\n";

    my $column_names = $csv->getline( $fh );

    $csv->column_names( $column_names );

    my $csv_dates = [];
    while ( my $csv_date = $csv->getline_hr( $fh ) )
    {
        push( @{ $csv_dates }, $csv_date );

        # print STDERR "$csv_date->{ stories_id } $csv_date->{ publish_date}\n";
    }

    die( "no rows found in csv" ) unless ( @{ $csv_dates } );

    die( "no stories_id column in csv" ) unless ( $csv_dates->[ 0 ]->{ stories_id } );

    die( "no publish_date column in csv" ) unless ( $csv_dates->[ 0 ]->{ publish_date } );

    return $csv_dates;
}

sub set_story_date
{
    my ( $db, $story, $epoch_csv_date, $publish_date ) = @_;

    my $epoch_db_date = Date::Parse::str2time( $story->{ publish_date } );

    if ( abs( $epoch_csv_date - $epoch_db_date ) > 60 )
    {
        my $sql_date = DateTime->from_epoch( epoch => ( $epoch_csv_date - ( 4 * 3600 ) ) )->datetime;

        print STDERR <<END;
$story->{ stories_id }: $story->{ publish_date } [ $epoch_db_date ] -> $sql_date / $publish_date [ $epoch_csv_date ]
END

        $db->query( "update stories set publish_date = ? where stories_id = ?", $sql_date, $story->{ stories_id } )
          unless ( $_debug );
        MediaWords::DBI::Stories::assign_date_guess_method( $db, $story, [ 'manual' ] );

        $_fixed_stories_map->{ $story->{ stories_id } } = 1;
    }

}

sub set_story_undateable
{
    my ( $db, $story ) = @_;

    MediaWords::DBI::Stories::assign_date_guess_method( $db, $story, 'undateable' );
    MediaWords::DBI::Stories::assign_date_guess_method( $db, $story, 'manual', 1 );

    print STDERR "$story->{ stories_id }: $story->{ publish_date } -> undateable\n";

    $_fixed_stories_map->{ $story->{ stories_id } } = 1;

}

# if the date in the csv_date is different from the date in the databse, set the
# date in the database
sub fix_date
{
    my ( $db, $csv_date ) = @_;

    return unless ( $csv_date->{ stories_id } );

    return if ( $_fixed_stories_map->{ $csv_date->{ stories_id } } );

    my $story = $db->find_by_id( 'stories', $csv_date->{ stories_id } );

    if ( !$story )
    {
        warn( "Unable to find story '$csv_date->{ stories_id }'" );
        return;
    }

    if ( $csv_date->{ dateable } && ( lc( $csv_date->{ dateable } ) eq 'no' ) )
    {
        set_story_undateable( $db, $story );
    }
    else
    {
        set_story_date( $db, $story, $csv_date->{ epoch_csv_date }, $csv_date->{ publish_date } );
    }
}

# parse all publish_date fields in the csv_dates and put the epoch date
# into epoch_publish_date.  we run this first, separately from the update
# to make sure that all dates will parse before updating anything.  this
# function will return 1 if all dates parse and undef otherwise.
sub parse_all_dates
{
    my ( $csv_dates ) = @_;

    my $all_dates_parsed = 1;
    my $i                = 0;
    for my $csv_date ( @{ $csv_dates } )
    {
        $i++;
        next if ( $csv_date->{ dateable } && ( lc( $csv_date->{ dateable } ) eq 'no' ) );
        my $publish_date = $csv_date->{ publish_date };

        # $csv_date->{ epoch_csv_date } = Date::Parse::str2time( $publish_date ) ||
        #     MediaWords::CM::GuessDate::timestamp_from_html( $publish_date );
        $csv_date->{ epoch_csv_date } = MediaWords::CM::GuessDate::timestamp_from_html( $publish_date );

        if ( !defined( $csv_date->{ epoch_csv_date } ) )
        {
            print STDERR "line [ $i ]: Unable to parse date '$publish_date'\n";
            $all_dates_parsed = undef;
        }
    }

    return $all_dates_parsed;
}

sub main
{
    my ( $csv, $_debug );

    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    Getopt::Long::GetOptions(
        "csv=s"  => \$csv,
        "debug!" => \$_debug,
    ) || return;

    die( "usage: $0 --csv < csv file > [ --debug ]" ) unless ( $csv );

    my $csv_dates = get_csv_dates( $csv );

    return unless ( parse_all_dates( $csv_dates ) );

    my $db = MediaWords::DB::connect_to_db;

    map { fix_date( $db, $_ ) } @{ $csv_dates };
}

main();
