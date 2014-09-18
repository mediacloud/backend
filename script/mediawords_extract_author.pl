#!/usr/bin/env perl

# run a loop extracting the text of any authors_stories_queue_items that have not been extracted yet

# usage: mediawords_extract_text.pl [<num of processes>]
#
# example:
# mediawords_extract_tags.pl 4 &

# number of authors_stories_queue to fetch at a time
use constant PROCESS_SIZE => 1;

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;

use MediaWords::DBI::Authors;
use MediaWords::Util::Process;
use Data::Dumper;

sub extract_author
{
    my ( $process_num, $num_processes ) = @_;

    my $db = MediaWords::DB::connect_to_db;

    $db->dbh->{ AutoCommit } = 0;

    while ( 1 )
    {
        print STDERR "[$process_num] find new authors_stories_queue_items ...\n";

        my $authors_stories_queue =
          $db->query( "SELECT d.* from authors_stories_queue d  where " . " d.state='queued'  and " .
"   (( ( d. authors_stories_queue_id + $process_num ) % $num_processes ) = 0 ) order by authors_stories_queue_id desc "
              . "  limit "
              . PROCESS_SIZE );

        my $authors_stories_queue_item_found;
        while ( my $authors_stories_queue_item = $authors_stories_queue->hash() )
        {
            $authors_stories_queue_item_found = 1;

            my $stories_id = $authors_stories_queue_item->{ stories_id };

            eval {

                $authors_stories_queue_item->{ state } = 'pending';

                $db->query( "update authors_stories_queue set state='pending' where authors_stories_queue_id=?",
                    $authors_stories_queue_item->{ authors_stories_queue_id } );

                my $story = $db->find_by_id( 'stories', $stories_id );

                my $content = MediaWords::DBI::Stories::get_initial_download_content( $db, $story );

                my $author = MediaWords::DBI::Authors::get_author_from_content( $content );

                if ( !$author )
                {
                    say STDERR "[$process_num] failed to get for author for $stories_id";
                    $db->query( "update authors_stories_queue set state='failed' where authors_stories_queue_id=?",
                        $authors_stories_queue_item->{ authors_stories_queue_id } );
                }
                else
                {

                    my $author_row = $db->find_or_create( 'authors', { author_name => $author } );

                    die "Failed to create author row " unless $author_row;

                    my $authors_id = $author_row->{ authors_id };

                    my $authors_stories_map_row =
                      $db->create( 'authors_stories_map', { authors_id => $authors_id, stories_id => $stories_id } );

                    $db->query( "update authors_stories_queue set state='success' where authors_stories_queue_id=?",
                        $authors_stories_queue_item->{ authors_stories_queue_id } );
                    say STDERR "[$process_num] Created authors_stories_map for $author & $stories_id";

                    #say STDERR  Dumper( $authors_stories_map_row );
                }
            };

            if ( $@ )
            {
                say STDERR "[$process_num] extractor error processing authors_stories_queue_item " .
                  $authors_stories_queue_item->{ authors_stories_queue_id } . ": $@";
                $db->rollback;
            }
        }

        $db->commit;

        if ( !$authors_stories_queue_item_found )
        {
            print STDERR "[$process_num] no authors_stories_queue found. sleeping ...\n";
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
                    extract_author( $i, $num_processes );
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
