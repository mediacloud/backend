#!/usr/bin/env perl
#
# Process CSV list stories against Bit.ly API
#
#
# Usage
# =====
#
#     ./script/run_with_carton.sh ./script/mediawords_bitly_process_csv_stories.pl stories.csv
#
# stories.csv should contain stories_id and URL as such:
#
#    183045817,http://www.iol.co.za/safa-remember-madiba-magic-1.1617700
#    193464034,http://armenpress.am/arm/news/745942/
#    ...
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Bitly;
use Text::CSV;
use Scalar::Util qw(looks_like_number);
use Data::Dumper;

sub main()
{
    unless ( $ARGV[ 0 ] )
    {
        die "Usage: $0 stories.csv\n";
    }

    my $stories_csv_file = $ARGV[ 0 ];
    unless ( -f $stories_csv_file )
    {
        die "File '$stories_csv_file' does not exist.\n";
    }

    my $csv = Text::CSV->new( { binary => 1 } )    # should set binary attribute.
      or die "Cannot use CSV: " . Text::CSV->error_diag();

    open my $fh, "<:encoding(utf8)", $stories_csv_file or die "Unable to open $stories_csv_file: $!";
    while ( my $row = $csv->getline( $fh ) )
    {

        if ( scalar( @{ $row } ) != 2 )
        {
            die "Only two columns with stories_id and URL is expected; got: " . Dumper( $row );
        }

        my $stories_id  = $row->[ 0 ];
        my $stories_url = $row->[ 1 ];

        unless ( looks_like_number( $stories_id ) )
        {
            die "The first column doesn't look like stories_id; got: " . Dumper( $row );
        }

        say STDERR "Processing story $stories_id...";
        my $c_stories_url = MediaWords::Util::Bitly::canonicalize_url( $stories_url );
        print Dumper( MediaWords::Util::Bitly::request( '/v3/link/lookup', { url => $c_stories_url } ) );
        say STDERR "Done.";
    }
    $csv->eof or $csv->error_diag();
    close $fh;
}

main();
