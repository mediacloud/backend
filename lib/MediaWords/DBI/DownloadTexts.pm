package MediaWords::DBI::DownloadTexts;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.download_texts' );

use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories::ExtractorArguments;

=head1 FUNCTIONS

=head2 get_extracted_html_from_db

Get extracted html for the download_text by using existing text extraction results.

=cut

sub get_extracted_html_from_db
{
    my ( $db, $download_text ) = @_;

    my $download = $db->find_by_id( 'downloads', $download_text->{ downloads_id } );

    my $args = MediaWords::DBI::Stories::ExtractorArguments->new( { use_cache => 1 } );

    my $extract = MediaWords::DBI::Downloads::extract( $db, $download, $args );

    return $extract->{ extracted_html };
}

1;
