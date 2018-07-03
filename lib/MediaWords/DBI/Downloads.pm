package MediaWords::DBI::Downloads;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.downloads' );

use MediaWords::DB;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::DBI::Stories::ExtractorArguments;
use MediaWords::Util::URL;

=head2 extract_and_create_download_text( $db, $download )

Extract the download and create a download_text from the extracted download.

=cut

sub extract_and_create_download_text($$$)
{
    my ( $db, $download, $extractor_args ) = @_;

    my $downloads_id = $download->{ downloads_id };

    TRACE "Extracting download $downloads_id...";

    my $extract = extract( $db, $download, $extractor_args );
    my $download_text;
    if ( $extractor_args->use_existing() )
    {
        $download_text =
          $db->query( "select * from download_texts where downloads_id = ?", $download->{ downloads_id } )->hash();
    }

    $download_text ||= MediaWords::DBI::DownloadTexts::create( $db, $download, $extract );

    return $download_text;
}

=head2 process_download_for_extractor( $db, $download, $extractor_args )

Extract the download create the resulting download_text entry.  If there are no remaining downloads to be extracted
for the story, call MediaWords::DBI::Stories::process_extracted_story() on the parent story.

=cut

sub process_download_for_extractor($$;$)
{
    my ( $db, $download, $extractor_args ) = @_;

    $extractor_args //= MediaWords::DBI::Stories::ExtractorArguments->new();

    my $stories_id = $download->{ stories_id };

    TRACE "extract: $download->{ downloads_id } $stories_id $download->{ url }";
    my $download_text = MediaWords::DBI::Downloads::extract_and_create_download_text( $db, $download, $extractor_args );

    my $has_remaining_download = $db->query( <<SQL, $stories_id )->hash;
SELECT downloads_id FROM downloads WHERE stories_id = ? AND extracted = 'f' AND type = 'content'
SQL

    if ( $has_remaining_download )
    {
        DEBUG "pending more downloads ...";
    }
    else
    {
        my $story = $db->find_by_id( 'stories', $stories_id );

        MediaWords::DBI::Stories::process_extracted_story( $db, $story, $extractor_args );
    }
}

1;
