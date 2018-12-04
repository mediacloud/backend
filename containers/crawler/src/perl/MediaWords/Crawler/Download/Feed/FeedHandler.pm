package MediaWords::Crawler::Download::Feed::FeedHandler;

#
# Handler for 'feed' downloads
#
# The feed handler parses the feed and looks for the urls of any new stories.
# A story is considered new if the url or guid is not already in the database
# for the given media source and if the story title is unique for the media
# source for the calendar week.  If the story is new, a story is added to the
# stories table and a download with a type of 'pending' is added to the
# downloads table.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;
with 'MediaWords::Crawler::Download::DefaultHandler';

# Return a list of new, to-be-fetcherd story IDs that were added from the feed
#
# For example, if 'syndicated' feed had three new stories, implementation would
# add them to "stories" table and return an arrayref of story IDs that are to
# be fetched later.
#
# If helper returns an empty arrayref, '(redundant feed)' will be written
# instead of feed contents.
requires 'add_stories_from_feed';

# Return a list of stories that have to be extracted from this feed
#
# For example, 'web_page' feed creates a single story for itself so it has to
# be extracted right away.
requires 'return_stories_to_be_extracted_from_feed';

use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;

use Readonly;

# Returns story IDs to extract
sub handle_download($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $downloads_id = $download->{ downloads_id };

    DEBUG "Processing feed download $downloads_id...";

    my ( $added_story_ids, $story_ids_to_extract );

    eval {
        $added_story_ids = $self->add_stories_from_feed( $db, $download, $decoded_content );
        $story_ids_to_extract = $self->return_stories_to_be_extracted_from_feed( $db, $download, $decoded_content );
    };
    if ( $@ )
    {
        my $error_message = "Error processing feed for download $downloads_id: $@";
        ERROR $error_message;

        $db->query(
            <<SQL,
            UPDATE downloads
            SET state = 'feed_error',
                error_message = ?
            WHERE downloads_id = ?
SQL
            $error_message, $downloads_id
        );

        $added_story_ids      = [];
        $story_ids_to_extract = [];
    }
    else
    {
        my $feeds_id = $download->{ feeds_id };

        my $last_new_story_time =
          scalar( @{ $added_story_ids } ) > 0
          ? 'last_new_story_time = last_attempted_download_time, '
          : '';

        $db->query(
            <<SQL,
            UPDATE feeds
            SET $last_new_story_time
                last_successful_download_time = greatest( last_successful_download_time, ? )
            WHERE feeds_id = ?
SQL
            $download->{ download_time }, $feeds_id
        );

        # if no new stories, just store (redudndant feed) to save storage space
        $decoded_content = '(redundant feed)' if ( scalar( @{ $added_story_ids } ) == 0 );
    }

    # Reread the possibly updated download
    $download = $db->find_by_id( 'downloads', $downloads_id );

    # Store the feed in any case
    $download = MediaWords::DBI::Downloads::store_content( $db, $download, $decoded_content );

    DEBUG "Done processing feed download $downloads_id";

    return $story_ids_to_extract;
}

1;
