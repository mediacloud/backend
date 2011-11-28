#!/usr/bin/perl

# import list of spidered russian blogs from csv

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Date::Parse;
use HTTP::Request;
use LWP::UserAgent;
use Text::CSV_XS;
use Text::Trim;

use DBIx::Simple::MediaWords;
use Feed::Scrape;
use MediaWords::DB;
use MediaWords::CommonLibs;

use Perl6::Say;
use Data::Dumper;
use LWP::Debug;
use MediaWords::Util::Translate;

sub main
{
    my ( $file, $out_file ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    if ( !$file || !$out_file )
    {
        die( "usage: mediawords_find_recently_updated_blogs.pl <csv file> <output file>\n" );
    }

    my $csv_in = Text::CSV_XS->new( { binary => 1 } ) || die "Cannot use CSV: " . Text::CSV_XS->error_diag();

    open( my $fh, "<:encoding(utf8)", $file ) or die "Unable to open file $file: $!\n";

    open( my $out_fh, ">", $out_file ) or die "Unable to create file $out_file: $!\n";

    my $in_header_line = $csv_in->getline( $fh );
    $csv_in->column_names( $in_header_line );

    my $csv_out = Text::CSV_XS->new( { binary => 1 } ) || die "Cannot use CSV: " . Text::CSV_XS->error_diag();
    my $output_header_line = [ @$in_header_line, 'translated' ];

    $csv_out->column_names( $output_header_line );

    $csv_out->print( $out_fh, $output_header_line );
    say $out_fh;

    my $media_added = 0;

    my $rows_processed = 0;

    my $recent_blogs = 0;
    my $old_blogs    = 0;

    while ( my $colref = $csv_in->getline( $fh ) )
    {

        my %hr;
        @hr{ @{ $csv_in->{ _COLUMN_NAMES } } } = @$colref;

        my $row = \%hr;

        my $term            = $row->{ term };
        my $translated_term = MediaWords::Util::Translate::translate( $term );

        $row->{ translated } = $translated_term;

        print STDERR "Recent blog $row->{url} $row->{rss} \n";

        #print STDERR "BLOGS ADDED: " . ++$media_added . "\n";

        my $out_colref = [ map { $row->{ $_ } } $csv_out->column_names ];
        $csv_out->print( $out_fh, $out_colref );
        say $out_fh;

        $rows_processed++;

        # if ( $rows_processed > 10 )
        # {
        #     last;
        # }
    }

}

main();

__END__
