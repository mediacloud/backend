#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

#use Test::More qw (no_plan);
use MediaWords::Crawler::Extractor qw (preprocess);
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use XML::LibXML;
use Encode;
use MIME::Base64;
use Getopt::Long;

sub main
{

    my $db = MediaWords::DB->authenticate();

    my $dbs = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info );

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'      => \$file,
        'downloads|d=s' => \@download_ids,
    ) or die "Usage program  -f | -d ";

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
    else
    {
        die "Must specify either a file or download_ids";
    }

    print "DOWNLOAD TEXT\n";

    for my $download ( @{ $downloads } )
    {
        print "DOWNLOAD TEXT\n";
        print MediaWords::DBI::Downloads::get_previously_extracted_text( $dbs, $download );
        print "\n";

    }
}

main();
