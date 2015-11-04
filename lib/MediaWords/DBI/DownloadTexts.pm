package MediaWords::DBI::DownloadTexts;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various helper functions for the download_texts table

use strict;
use warnings;

use Encode;

use Data::Dumper;

use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::DBI::Downloads;
use Try::Tiny;

#use Regexp::Optimizer;

## TODO rename this function
sub get_extracted_html_from_db
{
    my ( $db, $download_text ) = @_;

    my $download = $db->find_by_id( 'downloads', $download_text->{ downloads_id } );

    my $extract = MediaWords::DBI::Downloads::extractor_results_for_download( $db, $download );

    return $extract->{ extracted_html };
}

# extract the text from a download and store that text in download_texts.
# also add the extracted line numbers to extracted_lines
sub create_from_download
{
    my ( $db, $download ) = @_;

    my $downloads_id = $download->{ downloads_id };

    say STDERR "Calling extractor_results_for_download() for download $downloads_id...";
    my $extract = MediaWords::DBI::Downloads::extractor_results_for_download( $db, $download );
    say STDERR "Done calling extractor_results_for_download() for download $downloads_id.";

    # Due to a foreign key, deleting from download_texts will also delete the
    # corresponding extracted_lines entries
    $db->query( "DELETE FROM download_texts WHERE downloads_id = ?", $downloads_id );

    my $extracted_text = $extract->{ extracted_text };

    # say STDERR "EXTRACTED TEXT:\n**\n$extracted_text\n**\n";

    say STDERR "INSERTing extracted text for download $downloads_id...";
    my $download_text = $db->query(
        <<EOF,
            INSERT INTO download_texts ( download_text, downloads_id, download_text_length )
                VALUES ( \$1, \$2, char_length( \$1 ) )
                RETURNING *
EOF
        $extracted_text, $downloads_id
    )->hash;
    say STDERR "Done INSERTing extracted text for download $downloads_id.";

    if ( exists $extract->{ included_line_numbers } )
    {
        say STDERR "COPYing extracted lines for download $downloads_id...";
        my $included_line_numbers = $extract->{ included_line_numbers };
        $db->dbh->do( "COPY extracted_lines(download_texts_id, line_number) FROM STDIN" );
        foreach my $included_line_number ( @{ $included_line_numbers } )
        {
            $db->dbh->pg_putcopydata( $download_text->{ download_texts_id } . "\t" . $included_line_number . "\n" );
        }

        $db->dbh->pg_putcopyend();
        say STDERR "Done COPYing extracted lines for download $downloads_id.";
    }

    $db->query( "UPDATE downloads SET extracted = 't' WHERE downloads_id = ?", $downloads_id );

    return $download_text;
}

1;
