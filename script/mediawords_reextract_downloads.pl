#!/usr/bin/perl

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
use MediaWords::DBI::Downloads;
use MediaWords::DBI::DownloadTexts;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use XML::LibXML;
use Data::Dumper;
use Perl6::Say;
use Digest::SHA qw(sha1 sha1_hex sha1_base64);

#use XML::LibXML::CDATASection;
use Encode;
use MIME::Base64;
use Lingua::EN::Sentence::MediaWords;

#use XML::LibXML::Enhanced;

my $_re_generate_cache = 0;

Readonly my $output_dir => 'download_content_test_data';

sub reextract_downloads
{

    my $downloads = shift;

    my @downloads = @{ $downloads };

    say STDERR "Starting reextract_downloads";

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $download_results = [];

    my $dbs = MediaWords::DB::connect_to_db;

    for my $download ( @downloads )
    {
        die "Non-content type download: $download->{ downloads_id } $download->{ type } "
          unless $download->{ type } eq 'content';

        say "Processing download $download->{downloads_id}";

        MediaWords::DBI::Downloads::process_download_for_extractor( $dbs, $download, 0 );
    }
}

sub regenerate_download_texts_for_downloads
{

    my $downloads = shift;

    say STDERR "regenerate_download_texts_for_downloads";

    my $dbs = MediaWords::DB::connect_to_db;

    my @download_ids = map { $_->{ downloads_id } } @{ $downloads };

    #say Dumper ( [ @download_ids ] );

    my $download_texts =
      $dbs->query( " SELECT * from download_texts where downloads_id in (??) order by downloads_id", @download_ids )->hashes;

    #say Dumper ( $download_texts );

    my @downloads = @{ $downloads };

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    foreach my $download_text ( @$download_texts )
    {
        MediaWords::DBI::DownloadTexts::update_text( $dbs, $download_text );

	#say Dumper ( $download_text );
    }

    #return;

    for my $download ( @downloads )
    {
        die "Non-content type download: $download->{ downloads_id } $download->{ type } "
          unless $download->{ type } eq 'content';

        say "Processing download $download->{downloads_id}";
        my $remaining_download = $dbs->query(
            "select downloads_id from downloads " . "where stories_id = ? and extracted = 'f' and type = 'content' ",
            $download->{ stories_id } )->hash;
        if ( !$remaining_download )
        {
            my $story = $dbs->find_by_id( 'stories', $download->{ stories_id } );

            # my $tags = MediaWords::DBI::Stories::add_default_tags( $db, $story );
            #
            # print STDERR "[$process_num] download: $download->{downloads_id} ($download->{feeds_id}) \n";
            # while ( my ( $module, $module_tags ) = each( %{$tags} ) )
            # {
            #     print STDERR "[$process_num] $download->{downloads_id} $module: "
            #       . join( ' ', map { "<$_>" } @{ $module_tags->{tags} } ) . "\n";
            # }

	    say "Updating story sentence words ";

            MediaWords::StoryVectors::update_story_sentence_words( $dbs, $story );
        }
        else
        {
            print STDERR " pending more downloads ...\n";
        }
    }
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

    say STDERR @download_ids;

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
    }

    say STDERR Dumper( $downloads );

    die 'no downloads found ' unless scalar( @$downloads );

    say STDERR scalar( @$downloads ) . ' downloads';

    reextract_downloads( $downloads );
    #regenerate_download_texts_for_downloads( $downloads );
}

main();
