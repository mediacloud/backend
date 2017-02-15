#!/usr/bin/env perl
#
# Export feed downloads and their raw content from backup crawler
#
# Usage: on backup crawler, run:
#
#     # Export feed downloads to "mediacloud-feed-downloads.csv"
#     ./script/run_with_carton.sh \
#         ./script/import_export/export_feed_downloads_from_backup_crawler.pl > mediacloud-feed-downloads.csv
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::DBI::Downloads;

use Data::Dumper;
use Encode;
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

    my $db = MediaWords::DB::connect_to_db;

    my $column_names = $db->query( 'SELECT * FROM downloads LIMIT 0' )->columns;

    $column_names = [ grep { my $f = $_; !grep $_ eq $f, @columns_to_remove } @{ $column_names } ];

    push( @{ $column_names }, '_raw_download_content' );

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

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    $csv->combine( @{ $column_names } );
    print encode( 'utf8', $csv->string ) . "\n";

    my $n = 1;
    foreach my $downloads_id ( @{ $feed_downloads_ids } )
    {
        INFO "Exporting download $downloads_id ($n out of " . scalar( @{ $feed_downloads_ids } ) . ")...";
        ++$n;

        my $download = $db->find_by_id( 'downloads', $downloads_id );

        my $raw_download_content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download );

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
        $csv->combine( @row, $$raw_download_content_ref );

        my $encoded_csv_row;
        eval { $encoded_csv_row = encode( 'utf8', $csv->string ) . "\n"; };
        if ( $@ )
        {
            die "Unable to encode download " . Dumper( $download );
        }

        print $encoded_csv_row;
    }

    INFO "Done exporting " . scalar( @{ $feed_downloads_ids } ) . " feed downloads.";
}

main();
