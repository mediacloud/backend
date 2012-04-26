#!/bin/sh
#! -*-perl-*-
eval 'exec perl -x -wS $0 ${1+"$@"}'
  if 0;

use Feed::Find;
use Data::Dumper;
use Encode;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Feed::Scrape;

use strict;

use MediaWords::CommonLibs;
use LWP::Protocol::https;

sub process_url
{

    my ( $url ) = @_;

    Readonly my $debug_print => 0;

    print "$url\n" if $debug_print;

    my $ua = LWP::UserAgent->new;
    $ua->from( 'mediawords@cyber.law.harvard.edu' );
    $ua->agent( 'mediawords bot (http://cyber.law.harvard.edu)' );

    $ua->timeout( 20 );
    $ua->max_size( 1024 * 1024 );
    $ua->max_redirect( 15 );

    my $response = $ua->get( $url );

    my $ret = {};

    $ret->{ url } = $url;

    # Check the outcome of the response
    if ( $response->is_success )
    {
        my $final_url = $response->request->uri;

        say "URL final = $final_url" if $debug_print;

        my $content = $response->decoded_content;

        use HTML::TreeBuilder;
        use HTML::FormatText;
        use MediaWords::StoryVectors;

        my $tree = HTML::TreeBuilder->new;

        $tree->parse( $content );

        #$tree->dump;

        #say $tree->as_text(skip_dels => 1, extra_chars => '\xA0');
        #say $tree->as_HTML();
        say "Dumpinging formatted text" if $debug_print;
        my $formatted_text = $tree->format();

        say $formatted_text if $debug_print;

        my $words = MediaWords::StoryVectors::_tokenize( [ $formatted_text ] );

        my $word_counts = {};
        foreach my $word ( @{ $words } )
        {
            $word_counts->{ $word } ||= 0;
            $word_counts->{ $word }++;
        }

        say Dumper ( $word_counts ) if $debug_print;
        my $sorted_words = [ sort @{ [ keys %{ $word_counts } ] } ];

        my $sorted_counts = [ map { [ $_, $word_counts->{ $_ } ] } @{ $sorted_words } ];

        say Dumper $sorted_counts if $debug_print;

        $ret->{ final_url } = $final_url;

        $ret->{ formatted_text } = $formatted_text;
        $ret->{ sorted_counts }  = $sorted_counts;
    }
    else
    {
        $ret->{ final_url } = 'FAIL';
        print STDERR $response->status_line, "\n";
    }

    return $ret;
}

use Class::CSV;
my $fields = [ qw ( file url final_url formatted_text word_counts non_stop_word_counts    ) ];

#my $fields =   [keys %{ $url_info } ] ;

my $csv = Class::CSV->new( fields => $fields );

$csv->add_line( $fields );

my $lines = 0;

use Spreadsheet::WriteExcel;

# Create a new Excel workbook
my $workbook = Spreadsheet::WriteExcel->new( 'perl.xls' );

# Add a worksheet
my $worksheet = $workbook->add_worksheet();

# Write a formatted and unformatted string, row and column notation.
my $col = my $row = 0;
$worksheet->write( $row, $col, $fields );

foreach my $file ( @ARGV )
{
    open( my $fh, "<", "$file" )
      or die "cannot open < $file: $!";

    say STDERR "Opened $file";

  WHILE_LOOP:
    while ( my $url = <$fh> )
    {

        chomp( $url );
        chomp( $url );

        $url =~ s/\r//g;
        $url =~ s/\n//g;

        $lines++;

        #next WHILE_LOOP if ( $lines == 1 );

        #last WHILE_LOOP if ( $lines == 5 );

        #say STDERR "'". $url . "-'-";

        say STDERR Dumper( $url );

        #exit;

        my $url_info = process_url( $url );

        $url_info->{ file } = $file;

        my $non_stop_word_counts = [];

        my $word_and_count_list = [];

        if ( defined( $url_info->{ sorted_counts } ) )
        {
            $url_info->{ word_counts } = join ';', map { join ':', @{ $_ } } @{ $url_info->{ sorted_counts } };

            $non_stop_word_counts =
              [ grep { !MediaWords::Util::StopWords::get_tiny_stop_word_lookup()->{ $_->[ 0 ] } }
                  @{ $url_info->{ sorted_counts } } ];

            $word_and_count_list = [ map { join ':', @{ $_ } } @{ $non_stop_word_counts } ];
            $url_info->{ non_stop_word_counts } = join ';', @{ $word_and_count_list };
        }

        $url_info->{ sorted_counts } = undef;

        delete( $url_info->{ sorted_counts } );

        #$url_info->{ formatted_text } =~ s/\r//g;

        my %temp_hash   = %{ $url_info };
        my @fields_list = @{ $fields };

        #say Dumper ( [@temp_hash{ @fields_list } ] );

        #next;
        $worksheet->write( $lines, 0, [ @temp_hash{ @fields_list } ] );

        $worksheet->write( $lines, scalar( @fields_list ), $word_and_count_list );

        delete( $url_info->{ formatted_text } );

        $csv->add_line( $url_info );

        #exit;
    }
}

say STDERR "CSV dump";

say $csv->string;
