#!/usr/bin/env perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

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
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use Lingua::EN::Sentence::MediaWords;
use Perl6::Say;
use Data::Dumper;
use MediaWords::Util::HTML;
use MediaWords::Util::ExtractorTest;
use Data::Compare;
use Storable;
use MediaWords::DBI::Downloads;
use 5.14.2;

my $_re_generate_cache = 0;
my $_test_sentences    = 0;

my $_download_data_load_file;
my $_download_data_store_file;
my $_dont_store_preprocessed_lines;
my $_dump_training_data_csv;

# do a test run of the text extractor
sub main
{

    my $db = MediaWords::DB->authenticate();

    my $dbs = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'                      => \$file,
        'downloads|d=s'                 => \@download_ids,
    ) or die;

    my $downloads;

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


    foreach my $download ( @ { $downloads } )
    {
	MediaWords::DBI::Downloads::rewrite_downloads_content( $dbs, $download );
    }
}

main();
