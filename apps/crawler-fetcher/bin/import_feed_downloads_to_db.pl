#!/usr/bin/env perl
#
# Import feed downloads exported with "export_feed_downloads_from_backup_crawler.pl" back into database
#
# Usage: on production machine (database that is being imported to ), run:
#
#     # Import feed downloads from "mediacloud-feed-downloads.csv"
#     import_feed_downloads_to_db.pl mediacloud-feed-downloads.csv
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DB;
use MediaWords::Crawler::Engine;

use Data::Dumper;
use Readonly;
use Text::CSV_XS;

sub main
{
    binmode STDOUT, ":utf8";
    binmode STDERR, ":utf8";

    Readonly my $usage => "Usage: $0 mediacloud-feed-downloads.csv\n";

    unless ( $ARGV[ 0 ] )
    {
        die $usage;
    }

    my $import_csv_file = $ARGV[ 0 ];
    unless ( -f $import_csv_file )
    {
        die $usage;
    }

    # Autoflush
    $| = 1;

    my $db = MediaWords::DB::connect_to_db();

    my $csv = Text::CSV_XS->new(
        {    #
            binary         => 1,    #
            quote_empty    => 1,    #
            quote_space    => 1,    #
            blank_is_undef => 1,    #
            empty_is_undef => 0,    #
        }
    ) or die "" . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(UTF-8)", $import_csv_file;
    $csv->header( $fh );

    INFO "Importing downloads from $import_csv_file...";

    $db->begin;

    my $n = 1;
    while ( my $download = $csv->getline_hr( $fh ) )
    {

        INFO "Importing download $n...";
        ++$n;

        my $raw_download_content = $download->{ '_raw_download_content' };
        delete $download->{ '_raw_download_content' };

        # Cast some columns
        $download->{ feeds_id }   = $download->{ feeds_id }         ? int( $download->{ feeds_id } )   : undef;    # NULL
        $download->{ stories_id } = $download->{ stories_id }       ? int( $download->{ stories_id } ) : undef;    # NULL
        $download->{ parent }     = $download->{ parent }           ? int( $download->{ parent } )     : undef;    # NULL
        $download->{ priority }   = $download->{ piority }          ? int( $download->{ priority } )   : 0;        # NOT NULL
        $download->{ sequence }   = $download->{ sequence }         ? int( $download->{ sequence } )   : 0;        # NOT NULL
        $download->{ extracted }  = int( $download->{ extracted } ) ? 't'                              : 'f';

        # Will be rewritten by handle_download()
        $download->{ path } = '';

        $download = $db->create( 'downloads', $download );

        my $handler = MediaWords::Crawler::Engine::handler_for_download( $db, $download );
        $handler->handle_download( $db, $download, $raw_download_content );
    }

    INFO "Committing...";
    $db->commit;

    INFO "Done importing downloads from $import_csv_file.";
}

main();
