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
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::MC_Fork;
use Perl6::Say;

# extract, story, and tag downloaded text for a $process_num / $num_processes slice of downloads
sub extract_text
{
    my ( $process_num, $num_processes ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    while ( 1 )
    {
        my ( $num_downloads ) = $db->query(
            "SELECT count(*) from downloads d " . 
            "  where d.extracted='f' and d.type='content' and d.state='success' " )->flat;

        print STDERR "[$process_num] find new downloads ($num_downloads remaining) ...\n";

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
                MediaWords::DBI::Downloads::process_download_for_extractor( $db, $download, $process_num );

            };

            if ( $@ )
            {
                say STDERR "[$process_num] extractor error processing download " . $download->{ downloads_id } . ": $@";
		$db->rollback;
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
        if ( !mc_fork )
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
