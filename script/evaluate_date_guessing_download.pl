#!/usr/bin/env perl
#
# Download sample files for date guessing evaluation
#
# Params:
# * CSV file with the the columns which include at least:
#     * "stories_id" -- story's ID
#     * "url" -- story's URL
#
# Example:
#      ./script/run_with_carton.sh ./script/evaluate_date_guessing_download.pl t/data/cm_date_guessing_sample.csv t/data/cm_date_guessing_sample/
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

use LWP::Simple;
use Text::CSV;

sub main()
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    unless ( $ARGV[ 1 ] )
    {
        die "Usage: $0 urls_and_manual_dates_file.csv output_folder/\n";
    }

    my Readonly $urls_and_manual_dates_file = $ARGV[ 0 ];
    my Readonly $output_folder              = $ARGV[ 1 ];

    unless ( -e $urls_and_manual_dates_file )
    {
        die "File '$urls_and_manual_dates_file' does not exist.\n";
    }
    unless ( -d $output_folder )
    {
        die "Output folder '$output_folder' does not exist.\n";
    }

    my $csv = Text::CSV->new( { binary => 1 } ) or die "Cannot use CSV: " . Text::CSV->error_diag();
    open my $fh, "<:encoding(utf8)", $urls_and_manual_dates_file or die $urls_and_manual_dates_file . ": $!";
    $csv->column_names( $csv->getline( $fh ) );
    while ( my $row = $csv->getline_hr( $fh ) )
    {

        my $stories_id = $row->{ stories_id };
        my $url        = $row->{ url };

        say STDERR "URL: $url";

        my $html = get( $url ) || '';

        open( OUTPUT, ">$output_folder/$stories_id" );
        binmode OUTPUT, ":utf8";
        print OUTPUT $html;
        close( OUTPUT );
    }

    $csv->eof or $csv->error_diag();
    close $fh;
}

main();
