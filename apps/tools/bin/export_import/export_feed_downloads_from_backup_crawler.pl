#!/usr/bin/env perl
#
# Export feed downloads and their raw content from backup crawler
#
# Usage: on backup crawler, run:
#
#     # Export feed downloads to "mediacloud-feed-downloads.csv"
#     ./script/run_in_env.sh \
#         ./script/export_import/export_feed_downloads_from_backup_crawler.pl > mediacloud-feed-downloads.csv
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Downloads::Store;

use Text::CSV_XS;

sub main
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    # Autoflush
    $| = 1;

    my @columns_to_remove = (

        # Target database will determine "downloads_id" itself
        'downloads_id',

        # Target database will figure out where to store download itself
        'path',
    );

    my $db = MediaWords::DB::connect_to_db();

    $db->begin;

    my $column_names = $db->query( 'SELECT * FROM downloads LIMIT 0' )->columns;

    $column_names = [ grep { my $f = $_; !grep $_ eq $f, @columns_to_remove } @{ $column_names } ];

    # Fetch all download IDs first to save some memory
    my $feed_downloads_ids = $db->query(
        <<SQL,
        SELECT downloads_id
        FROM downloads
        WHERE type = 'feed'
          AND state IN ('success', 'feed_error')
        ORDER BY downloads_id
SQL
    )->flat;

    INFO "Exporting " . scalar( @{ $feed_downloads_ids } ) . " feed downloads...";

    my $csv = Text::CSV_XS->new(
        {    #
            binary         => 1,    #
            quote_empty    => 1,    #
            quote_space    => 1,    #
            blank_is_undef => 1,    #
            empty_is_undef => 0,    #
        }
    ) or die "" . Text::CSV_XS->error_diag();

    # Append raw content as last column
    $csv->combine( @{ $column_names }, '_raw_download_content' );
    print $csv->string . "\n";

    my $n = 1;
    foreach my $downloads_id ( @{ $feed_downloads_ids } )
    {
        INFO "Exporting download $downloads_id ($n out of " . scalar( @{ $feed_downloads_ids } ) . ")...";
        ++$n;

        my $download = $db->find_by_id( 'downloads', $downloads_id );

        my $raw_download_content = MediaWords::DBI::Downloads::Store::fetch_content( $db, $download );

        if ( $raw_download_content eq '(redundant feed)' )
        {
            INFO "Download $downloads_id is redundant feed, skipping...";
            next;
        }

        foreach my $column_to_remove ( @columns_to_remove )
        {
            delete $download->{ $column_to_remove };
        }

        my @row;
        foreach my $column_name ( @{ $column_names } )
        {
            push( @row, $download->{ $column_name } );
        }

        # Append raw content as last column
        $csv->combine( @row, $raw_download_content );

        print $csv->string . "\n";
    }

    $db->commit;

    INFO "Done exporting " . scalar( @{ $feed_downloads_ids } ) . " feed downloads.";
}

main();
