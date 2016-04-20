package MediaWords::DBI::DownloadTexts;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

MediaWords::DBI::DownloadTexts - various helper functions for the download_texts table

=cut

use strict;
use warnings;

use Encode;

use Data::Dumper;

use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::DBI::Downloads;
use Try::Tiny;

=head1 FUNCTIONS

=head2 get_extracted_html_from_db

Get extracted html for the download_text by using existing text extraction results.

=cut

sub get_extracted_html_from_db
{
    my ( $db, $download_text ) = @_;

    my $download = $db->find_by_id( 'downloads', $download_text->{ downloads_id } );

    my $extract = MediaWords::DBI::Downloads::extract( $db, $download );

    return $extract->{ extracted_html };
}

=head2 create( $db, $download, $extract )

Create a download_text hash and insert it into the database.  Delete any existing download_text row for the download.
update downloads.extracted to true.

=cut

sub create
{
    my ( $db, $download, $extract ) = @_;

    $db->query( "DELETE FROM download_texts WHERE downloads_id = ?", $download->{ downloads_id } );

    my $download_text = $db->query( <<SQL, $extract->{ extracted_text }, $download->{ downloads_id } )->hash;
INSERT INTO download_texts ( download_text, downloads_id, download_text_length )
    VALUES ( \$1, \$2, char_length( \$1 ) )
    RETURNING *
SQL

    $db->query( "UPDATE downloads SET extracted = 't' WHERE downloads_id = ?", $download->{ downloads_id } );

    return $download_text;
}

1;
