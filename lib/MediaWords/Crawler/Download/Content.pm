package MediaWords::Crawler::Download::Content;

#
# Handler for 'content' downloads
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::Crawler::Download::DefaultFetcher', 'MediaWords::Crawler::Download::DefaultHandler';

use MediaWords::DBI::Downloads;

sub handle_download($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $downloads_id = $download->{ downloads_id };
    my $stories_id   = $download->{ stories_id };

    unless ( $downloads_id )
    {
        die "downloads_id is empty";
    }
    unless ( $stories_id )
    {
        die "stories_id is empty";
    }
    unless ( defined $decoded_content )
    {
        die "Content for download $downloads_id, story $stories_id is undefined";
    }

    DEBUG "Processing content download $downloads_id (story $stories_id)...";

    if ( length( $decoded_content ) == 0 )
    {
        WARN "Content for download $downloads_id, story $stories_id is empty";
    }

    $download = MediaWords::DBI::Downloads::store_content( $db, $download, $decoded_content );

    DEBUG "Done processing content download $downloads_id (story $stories_id)";

    my $story_ids_to_extract = [ $download->{ stories_id } ];
    return $story_ids_to_extract;
}

1;
