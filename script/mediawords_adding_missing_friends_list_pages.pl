#!/usr/bin/perl

# run a loop extracting the text of any downloads that have not been extracted yet

# usage: mediawords_extract_text.pl [<process num> <num of processes>]
#
# to run several instances in parallel, supply the number of the given process and the total number of processes
# example:
# mediawords_extract_tags.pl 1 4 &
# mediawords_extract_tags.pl 2 4 &
# mediawords_extract_tags.pl 3 4 &
# mediawords_extract_tags.pl 4 4 &

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib "$FindBin::Bin/";
}

use Encode;
use MediaWords::DB;
use DBIx::Simple::MediaWords;
use List::Uniq ':all';
use TableCreationUtils;
use MediaWords::Crawler::BlogSpiderDbUtils;

sub main
{

    my ( $process_num, $num_processes ) = @ARGV;

    $process_num   ||= 1;
    $num_processes ||= 1;

    my $dbs = TableCreationUtils::get_database_handle()
      || die DBIx::Simple::MediaWords->error;

    my $found_blogs_processed = 0;

    my $found_blogs_id_window_start = 0;
    my $found_blogs_batch_size      = 1000;
    my $found_blogs_id_window_end   = $found_blogs_id_window_start + $found_blogs_batch_size;

    ( my $max_found_blogs_id ) = $dbs->query("select max(found_blogs_id) from found_blogs")->flat();

    while ( $found_blogs_id_window_start <= $max_found_blogs_id )
    {
        print STDERR "while(1) loop\n";

        my $found_blogs_batch_query =
          "SELECT * from found_blogs where found_blogs_id >= ? and found_blogs_id <= ? limit 200000 ";

        print STDERR "max found_blogs_id = $max_found_blogs_id\n";

        #$found_blogs_id_window_end = $max_found_blogs_id;

        print STDERR "Running query '$found_blogs_batch_query'\n";

        my $found_blogs = $dbs->query( $found_blogs_batch_query, $found_blogs_id_window_start, $found_blogs_id_window_end );

        print STDERR "query completed for $found_blogs_batch_query\n";

        my $found_blog_found;
        my $previous_processed_found_blog_end_time = time();
        while ( my $found_blog = $found_blogs->hash() )
        {

            $found_blogs_processed++;

            if ( $found_blogs_processed > 1000 )
            {

                #exit;
            }

            print STDERR ' while ( my $found_blog' . "\n";

            # ignore found_blogs for multi-processor runs
            if ( ( $found_blog->{found_blogs_id} + $process_num ) % $num_processes )
            {
                print STDERR "Ignoring  " . $found_blog->{found_blogs_id} . "  + $process_num \n";
                next;
            }

            print STDERR "processing found_blog id:"
              . $found_blog->{found_blogs_id} . "  -- "
              . ( ( time() ) - $previous_processed_found_blog_end_time )
              . " since last found_blog processed\n";

            $found_blog_found = 1;

            MediaWords::Crawler::BlogSpiderDbUtils::add_friends_list_page( $dbs, $found_blog->{url} );

            $previous_processed_found_blog_end_time = time();

        }    #end while

        if ( !$found_blog_found )
        {
            print STDERR "no found_blogs found. sleeping ...\n";

            sleep 1;

          #             print STDERR "incrementing found_blogs_id window ...\n";
          #             $found_blogs_id_window_start += $found_blogs_batch_size;
          #             $found_blogs_id_window_end   += $found_blogs_batch_size;
          #             print STDERR "found_blogs_id windows: $found_blogs_id_window_start -  $found_blogs_id_window_end \n";
        }

        print STDERR "Completed batches of found_blog text extraction and storage\n";

        print STDERR
"Completed window $found_blogs_id_window_start - $found_blogs_id_window_end (max found_blogs_id: $max_found_blogs_id)\n";

        $found_blogs_id_window_start = $found_blogs_id_window_end;
        $found_blogs_id_window_end += $found_blogs_batch_size;
    }
}

eval { main(); };

print "exit: $@\n";
