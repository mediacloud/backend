#!/usr/bin/env perl

#
# Download various sources for the language detection module evaluation script.
#
# Usage: ./langid_download.pl --sources_xml=emm_sources.xml --destination_dir=output/
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

use XML::Simple;
use LWP::Simple;

sub download_pages_from_emm_sources_xml
{
    my ( $sources_xml_filename, $destination_dir ) = @_;
    die "Sources XML file '$sources_xml_filename' does not exist.\n"   unless ( -e $sources_xml_filename );
    die "Destination directory already exists (I prefer it didn't).\n" unless ( !-e $destination_dir );

    # Create output directory
    mkdir $destination_dir or die $!;

    # Language ID -> source index mapping
    # (e.g. "lt" => 3) -- it means there exists lt_0001.html, lt_0002.html and lt_0003.html already
    my %language_id_source_index = ();

    # Parse XML
    my $xml  = new XML::Simple;
    my $data = $xml->XMLin( $sources_xml_filename );

    foreach my $source_key ( keys %{ $data->{ source } } )
    {
        my $source = $data->{ source }->{ $source_key };

        # Get parameters from the XML source file
        my $url = $source->{ url };
        if ( length( $url ) == 0 )
        {
            print STDERR "URL length for source '$source_key' is zero.\n";
            next;
        }
        my $lang = $source->{ lang };
        if ( length( $lang ) == 0 )
        {
            print STDERR "Language length for source '$source_key' is zero.\n";
            next;
        }

        # Fetch the source
        print STDERR "Fetching source '$source_key'... ";    # intentionally no linebreak
        my $content = get( $url );
        unless ( defined $content and length( $content ) > 0 )
        {
            print STDERR "Couldn't fetch source '$source_key' from URL '$url', giving up.\n";
            next;
        }

        # Increase the language index
        if ( !exists $language_id_source_index{ $lang } )
        {
            $language_id_source_index{ $lang } = 1;
        }
        else
        {
            ++$language_id_source_index{ $lang };
        }
        my $source_index = $language_id_source_index{ $lang };

        # Target filename and path
        my $target_filename = sprintf( '%s_%04d.html', $lang, $source_index );
        my $target_path = $destination_dir . '/' . $target_filename;

        # Write
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
    my $sources_xml     = '';
    my $destination_dir = '';

    my Readonly $usage = 'Usage: ./langid_download.pl --sources_xml=emm_sources.xml --destination_dir=destination_dir/';

    GetOptions(
        'sources_xml=s'     => \$sources_xml,
        'destination_dir=s' => \$destination_dir,
    ) or die "$usage\n";
    die "$usage\n" unless ( $sources_xml     ne '' );
    die "$usage\n" unless ( $destination_dir ne '' );

    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    print STDERR "starting --  " . localtime() . "\n";

    download_pages_from_emm_sources_xml( $sources_xml, $destination_dir );

    print STDERR "finished --  " . localtime() . "\n";
}

main();
