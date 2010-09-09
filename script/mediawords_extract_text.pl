#!/usr/bin/perl -w

# run a loop extracting the text of any downloads that have not been extracted yet

# usage: mediawords_extract_text.pl [<num of processes>]
#
# example:
# mediawords_extract_tags.pl 4 &

# number of downloads to fetch at a time
use constant PROCESS_SIZE => 100;

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use Perl6::Say;

sub _process_download
{

    my ( $db, $download, $process_num ) = @_;

    print STDERR "[$process_num] extract: $download->{ downloads_id } $download->{ stories_id } $download->{ url }\n";
    my $download_text = MediaWords::DBI::DownloadTexts::create_from_download( $db, $download );

    my $remaining_download =
      $db->query( "select downloads_id from downloads " . "where stories_id = ? and extracted = 'f' and type = 'content' ",
        $download->{ stories_id } )->hash;
    if ( !$remaining_download )
    {
        my $story = $db->find_by_id( 'stories', $download->{ stories_id } );

        # my $tags = MediaWords::DBI::Stories::add_default_tags( $db, $story );
        #
        # print STDERR "[$process_num] download: $download->{downloads_id} ($download->{feeds_id}) \n";
        # while ( my ( $module, $module_tags ) = each( %{$tags} ) )
        # {
        #     print STDERR "[$process_num] $download->{downloads_id} $module: "
        #       . join( ' ', map { "<$_>" } @{ $module_tags->{tags} } ) . "\n";
        # }

        MediaWords::StoryVectors::update_story_sentence_words( $db, $story );
    }
    else
    {
        print STDERR "[$process_num] pending more downloads ...\n";
    }

}

# extract, story, and tag downloaded text for a $process_num / $num_processes slice of downloads
sub extract_text
{
    my ( $process_num, $num_processes ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    while ( 1 )
    {
        print STDERR "[$process_num] find new downloads ...\n";

        my $downloads = $db->query(
            "SELECT d.* from downloads d " . "  where d.extracted='f' and d.type='content' and d.state='success' " .
              "    and  (( ( d.feeds_id + $process_num ) % $num_processes ) = 0 ) " . " order by stories_id desc " .
              "  limit " . PROCESS_SIZE );

        # my $downloads = $db->query( "select * from downloads where stories_id = 418981" );
        my $download_found;
        while ( my $download = $downloads->hash() )
        {
            $download_found = 1;

            eval {
                _process_download( $db, $download, $process_num );

            };

            if ( $@ )
            {
                say STDERR "[$process_num] extractor error processing download " . $download->{ downloads_id } . ": $@";
            }
        }

        $db->commit;

        if ( !$download_found )
        {
            print STDERR "[$process_num] no downloads found. sleeping ...\n";
            sleep 60;
        }

    }
}

# fork of $num_processes
sub main
{
    my ( $num_processes ) = @ARGV;

    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    $num_processes ||= 1;

    # turn off buffering so processes don't write over each other as much
    $| = 1;

    for ( my $i = 0 ; $i < $num_processes ; $i++ )
    {
        if ( !fork )
        {
            while ( 1 )
            {
                eval {
                    print STDERR "[$i] START\n";
                    extract_text( $i, $num_processes );
                };
                if ( $@ )
                {
                    print STDERR "[$i] extract_text failed with error: $@\n";
                    print STDERR "[$i] sleeping before restart ...\n";
                    sleep 60;
                }
            }
        }
    }

    while ( wait > -1 )
    {
    }
}

main();
