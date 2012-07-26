#!/usr/bin/perl

#Simple script to fill in the download_text_length field of downloads_texts.

#Yes we could do this with a SQL query but we want the operation to be non atomic so that the table isn't locked.

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

BEGIN
{
    use constant MODULES => qw(Calais);

    for my $module ( MODULES )
    {
        eval( "use MediaWords::Tagger::${module};" );
        if ( $@ )
        {
            die( "error loading $module: $@" );
        }
    }
}

use Encode;
use MediaWords::DB;
use DBIx::Simple;
use DBIx::Simple::MediaWords;
use MediaWords::Tagger;
use MediaWords::Crawler::Extractor;
use MediaWords::DBI::Downloads;
use List::Uniq ':all';

sub main
{

    my ( $process_num, $num_processes ) = @ARGV;

    $process_num   ||= 1;
    $num_processes ||= 1;

    my $db = MediaWords::DB->authenticate();

    my $dbs = MediaWords::DB::connect_to_db()
      || die DBIx::Simple::MediaWords->error;

    my $download_texts_processed = 0;

    my $download_texts_id_window_start = 0;
    my $download_texts_batch_size      = 100;
    my $download_texts_id_window_end   = $download_texts_id_window_start + $download_texts_batch_size;

    ( my $max_download_texts_id ) = $dbs->query( "select max(download_texts_id) from download_texts" )->flat();

    while ( $download_texts_id_window_start < $max_download_texts_id )
    {
        $dbs->query(
"UPDATE download_texts set download_text_length = length(download_text) where download_text_length is null and download_texts_id >= ? and download_texts_id <= ? ",
            $download_texts_id_window_start, $download_texts_id_window_end
        );

        print STDERR "Completed window $download_texts_id_window_start - $download_texts_id_window_end \n";

        $download_texts_id_window_start = $download_texts_id_window_end;
        $download_texts_id_window_end += $download_texts_batch_size;

        #($max_download_texts_id) = $dbs->query("select max(download_texts_id) from download_texts")->flat();
    }
}

eval { main(); };

print "exit: $@\n";
