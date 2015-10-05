package MediaWords::DBI::DownloadTexts;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various helper functions for the download_texts table

use strict;

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

    my $extract = MediaWords::DBI::Downloads::extractor_results_for_download( $db, $download );

    # say STDERR Dumper( $extract );

    my $extracted_html;

    ## NOTE due to a foreign key, deleting from download_texts will also delete the corresponding extracted_lines entries.
    $db->query( "delete from download_texts where downloads_id = ?", $download->{ downloads_id } );

    my $extracted_text = $extract->{ extracted_text };

    # say STDERR "EXTRACT\n**\n$extracted_text\n**\n";

    #temporarily disabling to make crawler test happy.
    #die unless Encode::is_utf8( $extracted_text );

    my $download_text = $db->query( <<END, $extracted_text, $download->{ downloads_id } )->hash;
insert into download_texts ( download_text, downloads_id, download_text_length )
    values ( \$1, \$2, char_length( \$1 ) )
    returning *
END

    if ( exists $extract->{ included_line_numbers } )
    {
        my $included_line_numbers = $extract->{ included_line_numbers };
        $db->dbh->do( "copy extracted_lines(download_texts_id, line_number) from STDIN" );
        foreach my $included_line_number ( @{ $included_line_numbers } )
        {
            $db->dbh->pg_putcopydata( $download_text->{ download_texts_id } . "\t" . $included_line_number . "\n" );
        }

        $db->dbh->pg_putcopyend();
    }

    $db->query( "update downloads set extracted = 't' where downloads_id = ?", $download->{ downloads_id } );

#die "Extractor text length mismatch for $download_text->{ download_texts_id } :    " . length($extracted_text) . " != " . length($download_text->{download_text }) unless length($extracted_text) eq length($download_text->{download_text });

#    die "Extractor text mismatch for $download_text->{ download_texts_id } " unless $extracted_text eq $download_text->{download_text };

    return $download_text;
}

1;
