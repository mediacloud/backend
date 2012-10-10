#!/usr/bin/env perl

#
# Extract plain, UTF-8 encoded text from the HTML pages downloaded by langid_preprocess.pl
#
# Usage: ./langid_preprocess.pl --source_dir=dir_with_html_files/ --destination_dir=output/
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;
use Getopt::Long;

use HTML::FormatText;
use LWP::UserAgent;    # HTTP::Message does the character encoding to UTF-8 for us via decoded_content()
use File::Basename;

# Strip HTML "the proper way": http://learn.perl.org/faq/perlfaq9.html#How-do-I-remove-HTML-from-a-string-
#
# Notes:
# * HTML::FormatText says it "outputs plain latin1 text", but UTF-8 input seems to work fine
# * HTML::FormatText is not perfect either, complains about "deep recursion" here and there
# * If you have trouble with Japanese characters, double-check the font that you're using
sub _strip_html
{
    my $html = shift;

    # Strip some tags manually (they don't get caught by the formatter)
    $html =~ s|<script.+?</script>||gsi;
    $html =~ s|<noscript.+?</noscript>||gsi;
    $html =~ s|<style.+?</style>||gsi;

    # Format HTML as text
    $html = HTML::FormatText->format_string( $html, leftmargin => 0, rightmargin => 80 );

    # Remove "[IMAGE]" remarks inserted by the formatter
    $html =~ s|\[IMAGE\]||gsi;
    $html =~ s|\n\n+|\n|gs;

    return $html;
}

sub convert_html_files_to_txt
{
    my ( $source_dir, $destination_dir ) = @_;

    die "Source directory '$source_dir' does not exist.\n" unless ( -d $source_dir );
    if ( !-d $destination_dir )
    {
        # Create output directory
        mkdir $destination_dir or die $!;
    }

    my $ua = LWP::UserAgent->new;

    my @html_files = <$source_dir/*.html>;
    foreach my $filepath ( @html_files )
    {

        print STDERR "Preprocessing file at path '$filepath'... ";    # intentionally no linebreak

        # Fetch file content via LWP, decode too
        my $response = $ua->get( 'file://' . $filepath );
        unless ( $response->is_success )
        {
            print STDERR "Unable to fetch file at path '$filepath' ({$response->status_line}), skipping...\n";
            next;
        }
        my $content = $response->decoded_content;
        die "File at path '$filepath' is empty.\n" unless $content ne '';

        # Strip HTML
        $content = _strip_html( $content );
        die "File at path '$filepath' is empty after stripping HTML.\n" unless $content ne '';

        # Write
        my ( $filename, $directories, $suffix ) = fileparse( $filepath, qr/\.[^.]*/ );
        my $target_filename = $filename . '.txt';
        my $target_path     = $destination_dir . '/' . $target_filename;
        print STDERR "Writing to '$target_filename'... ";    # intentionally no linebreak
        open( SAMPLE_FILE, '>' . $target_path ) or die "Unable to open file '$target_path' for writing\n";
        binmode( SAMPLE_FILE, ":utf8" );
        print SAMPLE_FILE $content;
        close( SAMPLE_FILE );

        print STDERR "Done.\n";
    }

    print STDERR "All done.\n";
}

sub main
{
    my $source_dir      = '';
    my $destination_dir = '';

    my Readonly $usage = 'Usage: ./langid_preprocess.pl --source_dir=dir_with_html_files/ --destination_dir=output/';

    GetOptions(
        'source_dir=s'      => \$source_dir,
        'destination_dir=s' => \$destination_dir,
    ) or die "$usage\n";
    die "$usage\n" unless ( $source_dir      ne '' );
    die "$usage\n" unless ( $destination_dir ne '' );

    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    print STDERR "starting --  " . localtime() . "\n";

    convert_html_files_to_txt( $source_dir, $destination_dir );

    print STDERR "finished --  " . localtime() . "\n";
}

main();
