#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use MediaWords::DBI::DownloadTexts;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use XML::LibXML;
use Data::Dumper;

use Digest::SHA qw(sha1 sha1_hex sha1_base64);

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;
use MediaWords::Languages::en;
use File::Temp;
use File::Slurp;
use Time::HiRes qw ( time);

#use XML::LibXML::Enhanced;

my $_re_generate_cache = 0;

Readonly my $output_dir => 'download_content_test_data';

Readonly my $goose_dir => '/space/mediacloud/goose/goose';

sub create_base64_encoded_element
{
    my ( $name, $content ) = @_;

    my $ret = XML::LibXML::Element->new( $name );

    my $data_section = XML::LibXML::CDATASection->new( encode_base64( encode( "utf8", $content ) ) );

    $ret->appendChild( $data_section );

    return $ret;
}

sub store_preprocessed_result
{
    my ( $download, $preprocessed_lines, $extract_results, $content_refx ) = @_;

    say STDERR "starting store_preprocessed_result";
    say STDERR "downloads_id: " . $download->{ downloads_id };

    my $lines_concated = join "", map { $_ . "\n" } @{ $preprocessed_lines };

    say STDERR "Preprocessed_lines:\n";

    MediaWords::DBI::DownloadTexts::update_extractor_results_with_text_and_html( $extract_results );

    #say STDERR "EXTRACTED HTML $extract_results->{ extracted_html }";
    #say STDERR "EXTRACTED TEXT $extract_results->{ extracted_text }";

    #say STDERR "Starting get_sentences ";
    #my $lang = MediaWords::Languages::en->new();
    #my $sentences = $lang->get_sentences( $extract_results->{ extracted_text } ) || return;

    #say STDERR "Finished get_sentences ";

    #say Dumper( $sentences );

    return;
}

sub extract_with_goose
{
    my ( $content_ref, $url ) = @_;

    my $temp_dir = File::Temp::tempdir || die( "Unable to create temp dir" );

    say STDERR "Directory '$temp_dir'";

    Readonly my $raw_html_file => "$temp_dir/article.html";

    open( FILE, "> $raw_html_file" ) || die "$@";

    say FILE $$content_ref;

    close( FILE );

    my $extracted_text_file = "$temp_dir/output.txt";
    my $system_command =
"cd $goose_dir; mvn exec:java -Dexec.mainClass=com.gravity.goose.TalkToMeGoose -Dexec.args='$url $raw_html_file' -e -q > $extracted_text_file";

    say STDERR $system_command;

    system( $system_command );

    my $extracted_text = read_file( $extracted_text_file );

    $extracted_text =~ s/^\+ Error stacktraces are turned on\.//;
    return $extracted_text;
}

sub store_downloads
{

    my $downloads = shift;

    my @downloads = @{ $downloads };

    say STDERR "Starting store_downloads";

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $download_results = [];

    my $dbs = MediaWords::DB::connect_to_db;

    for my $download ( @downloads )
    {
        say "Processing download $download->{downloads_id}";

        my $content_ref = MediaWords::DBI::Downloads::fetch_content( $dbs, $download );

        my $extract_results;
        my $preprocessed_lines;

        my $mc_extract_start_time = time;

        for my $i ( 0 .. 100 )
        {
            say $i;
            $preprocessed_lines = MediaWords::DBI::Downloads::fetch_preprocessed_content_lines( $dbs, $download );
            $extract_results = MediaWords::DBI::Downloads::extract( $dbs, $download );

            store_preprocessed_result( $download, $preprocessed_lines, $extract_results, $content_ref );
        }

        my $mc_extract_stop_time = time;

        my $goose_extract_start_time = time;

        my $goose_extracted = extract_with_goose( $content_ref, $download->{ url } );

        my $goose_extract_stop_time = time;

        say STDERR $goose_extracted;

        my $score =
          Text::Similarity::Overlaps->new( { normalize => 1, verbose => 0 } )
          ->getSimilarityStrings( $goose_extracted, $extract_results->{ extracted_text } );

        say "similarity score: $score";

        say "media cloud time: ( $mc_extract_stop_time - $mc_extract_start_time ); " .
          ( $mc_extract_stop_time - $mc_extract_start_time );
        say "goose time: ( $goose_extract_stop_time - $goose_extract_start_time );" .
          ( $goose_extract_stop_time - $goose_extract_start_time );
    }

}

sub create_download_element
{
    my ( $download ) = @_;

    my $download_element = XML::LibXML::Element->new( 'download' );
    foreach my $key ( sort keys %{ $download } )
    {
        $download_element->appendTextChild( $key, $download->{ $key } );
    }

    return $download_element;
}

# do a test run of the text extractor
sub main
{

    my $dbs = MediaWords::DB::connect_to_db;

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'                  => \$file,
        'downloads|d=s'             => \@download_ids,
        'regenerate_database_cache' => \$_re_generate_cache,
    ) or die;

    unless ( $file || ( @download_ids ) )
    {
        die "no options given ";
    }

    my $downloads;

    say STDERR Dumper( [ @download_ids ] );

    if ( @download_ids )
    {
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    elsif ( $file )
    {
        open( DOWNLOAD_ID_FILE, $file ) || die( "Could not open file: $file" );
        @download_ids = <DOWNLOAD_ID_FILE>;
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    else
    {
        die "must specify file or downloads id";

        $downloads = $dbs->query(
"SELECT * from downloads where downloads_id in (select distinct downloads_id from extractor_training_lines order by downloads_id)"
        )->hashes;
    }

    say STDERR Dumper( $downloads );

    die 'no downloads found ' unless scalar( @$downloads );

    say STDERR scalar( @$downloads ) . ' downloads';
    store_downloads( $downloads );
}

main();
