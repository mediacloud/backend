#!/usr/bin/env perl

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
use XML::LibXML;
use Data::Dumper;

use Digest::SHA qw(sha1 sha1_hex sha1_base64);

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;

# do a test run of the text extractor
sub main
{

    my $file;
    my @stories_ids;

    GetOptions(
        'file|f=s'    => \$file,
        'stories|s=s' => \@stories_ids,
    ) or die;

    unless ( $file || ( @stories_ids ) )
    {
        die "no options given ";
    }

    my $downloads;

    if ( @stories_ids )
    {
        ;
    }
    elsif ( $file )
    {
        open( STORIES_ID_FILE, $file ) || die( "Could not open file: $file" );
        @stories_ids = <STORIES_ID_FILE>;

        #say Dumper ( [ @stories_ids ] );
    }
    else
    {
        die "must specify file or stories id";
    }

    @stories_ids = map { chomp( $_ ); $_ } @stories_ids;

    #say Dumper ( [ @stories_ids ] );

    my $dbs = MediaWords::DB::connect_to_db;

    foreach my $stories_id ( @stories_ids )
    {
        say STDERR "'$stories_id'";
        $dbs->query( "UPDATE downloads SET extracted = 't' where stories_id = ? and type='content'", $stories_id );
    }
}

main();
