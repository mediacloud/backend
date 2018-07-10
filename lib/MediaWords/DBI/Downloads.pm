package MediaWords::DBI::Downloads;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.dbi.downloads' );

use MediaWords::DB;
use MediaWords::DBI::Stories::ExtractorArguments;
use MediaWords::DBI::Stories::Process;

=head2 process_download_for_extractor( $db, $download, $extractor_args )

Extract the download create the resulting download_text entry.  If there are no remaining downloads to be extracted
for the story, call MediaWords::DBI::Stories::Process::process_extracted_story() on the parent story.

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

        MediaWords::DBI::Stories::Process::process_extracted_story( $db, $story, $extractor_args );
    }
}

=head2 _get_first_download( $db, $download )

Get the first download linking to this story.

=cut

sub _get_first_download
{
    my ( $db, $story ) = @_;

    return $db->query( <<SQL, $story->{ stories_id } )->hash;
SELECT * FROM downloads WHERE stories_id = ? ORDER BY sequence ASC LIMIT 1
SQL
}

=head2 get_content_for_first_download( $db, $story )

Call fetch_content on the result of _get_first_download().  Return undef if the download's state is not null.

=cut

sub get_content_for_first_download($$)
{
    my ( $db, $story ) = @_;

    my $first_download = _get_first_download( $db, $story );

    if ( $first_download->{ state } ne 'success' )
    {
        DEBUG "First download's state is not 'success' for story " . $story->{ stories_id };
        return;
    }

    my $content = fetch_content( $db, $first_download );

    return $content;
}

1;
