#!/usr/bin/env perl

# dump download to file

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Downloads;
use MediaWords::DBI::DownloadTexts;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Data::Dumper;

use Digest::SHA qw(sha1 sha1_hex sha1_base64);

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;

sub dump_downloads_to_file
{

    my $downloads = shift;

    my @downloads = @{ $downloads };

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $db = MediaWords::DB::connect_to_db;

    for my $download ( @downloads )
    {
        my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download );

        my $downloads_id = $download->{ downloads_id };

        my $filename = "download_$downloads_id.html";

        open my $out, '>:encoding(UTF-8)', $filename;

        print { $out } $$content_ref;

        close( $out );

        say STDERR "saved in file $filename";

    }
}

# do a test run of the text extractor
sub main
{

    my $dbs = MediaWords::DB::connect_to_db;

    my $file;
    my @download_ids;
    my $query;

    GetOptions(
        'downloads|d=s' => \@download_ids,
        'query|q=s'     => \$query
    ) or die;

    unless ( @download_ids || $query )
    {
        die "no options given ";
    }

    my $downloads;

    if ( @download_ids )
    {
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    else
    {
        $downloads = $dbs->query( $query )->hashes;
    }

    die 'no downloads found ' unless scalar( @$downloads );

    say STDERR scalar( @$downloads ) . ' downloads';

    dump_downloads_to_file( $downloads );
    say STDERR "completed dumpings";
}

main();
