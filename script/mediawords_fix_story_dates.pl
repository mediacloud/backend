#!/usr/bin/env perl

# accept a csv with a stories_id and a publish_date field.  change any dates
# that are different in the csv than in the existing story.

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Date::Parse;
use DateTime;
use Text::CSV_XS;

use MediaWords::DB;

# hash of fixed stories to avoid resetting a story once it has been fixed
my $_fixed_stories_map = {};

# parse the csv file and return a hash with a stories_id and publish_date field
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

    my $epoch_csv_date = Date::Parse::str2time( $csv_date->{ publish_date } );
    my $epoch_db_date  = Date::Parse::str2time( $story->{ publish_date } );

    if ( abs( $epoch_csv_date - $epoch_db_date ) > 60 )
    {
        my $sql_date = DateTime->from_epoch( epoch => ( $epoch_csv_date - ( 4 * 3600 ) ) )->datetime;

        print STDERR
"$story->{ stories_id }: $story->{ publish_date } [ $epoch_db_date ] -> $sql_date / $csv_date->{ publish_date } [ $epoch_csv_date ]\n";
        $db->query( "update stories set publish_date = ? where stories_id = ?", $sql_date, $story->{ stories_id } );

        $_fixed_stories_map->{ $csv_date->{ stories_id } } = 1;
    }
}

sub main
{
    my ( $csv_file ) = @ARGV;

    die( "usage: $0 <csv file>" ) unless ( $csv_file );

    my $db = MediaWords::DB::connect_to_db;

    my $csv_dates = get_csv_dates( $csv_file );

    map { fix_date( $db, $_ ) } @{ $csv_dates };
}

main();
