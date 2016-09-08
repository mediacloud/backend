package MediaWords::Crawler::Download::FeedHandler;

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
with 'MediaWords::Crawler::DefaultHandler';

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

sub _feed_processing_is_disabled($)
{
    my $self = shift;

    my $config = MediaWords::Util::Config::get_config;
    if (   ( $config->{ mediawords }->{ do_not_process_feeds } )
        && ( $config->{ mediawords }->{ do_not_process_feeds } eq 'yes' ) )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Returns story IDs to extract
sub handle_download($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $downloads_id = $download->{ downloads_id };

    DEBUG "Processing feed download $downloads_id...";

    my $story_ids_to_extract = [];

    if ( $self->_feed_processing_is_disabled() )
    {
        WARN "DO NOT PROCESS FEEDS";
        $db->update_by_id(
            'downloads',
            $download->{ downloads_id },
            { state => 'feed_error', error_message => 'do_not_process_feeds' }
        );

        $story_ids_to_extract = [];
    }
    else
    {
        my $added_story_ids = [];
        eval {
            $added_story_ids = $self->add_stories_from_feed( $db, $download, $decoded_content );
            $story_ids_to_extract = $self->return_stories_to_be_extracted_from_feed( $db, $download, $decoded_content );
        };
        if ( $@ )
        {
            $download->{ state } = 'feed_error';
            my $error_message = "Error processing feed: $@";
            ERROR $error_message;
            $download->{ error_message } = $error_message;
        }
        else
        {
            $db->query(
                <<SQL,
                UPDATE feeds
                SET last_successful_download_time = greatest( last_successful_download_time, ? )
                WHERE feeds_id = ?
SQL
                $download->{ download_time }, $download->{ feeds_id }
            );
        }

        if ( scalar( @{ $added_story_ids } ) > 0 )
        {
            $db->query(
                <<SQL,
                UPDATE feeds
                SET last_new_story_time = last_attempted_download_time
                WHERE feeds_id = ?
SQL
                $download->{ feeds_id }
            );
        }
        else
        {
            # If the feed didn't come up with any new stories, we store
            # '(redundant feed)' as the content of the feed and do not check
            # for new stories.  This prevents frequent storage of redundant
            # feed content and also avoids the considerable processing time
            # required to check individual urls for new stories.
            $decoded_content = '(redundant feed)';
        }
    }

    MediaWords::DBI::Downloads::store_content( $db, $download, \$decoded_content );

    DEBUG "Done processing feed download $downloads_id";

    return $story_ids_to_extract;
}

1;
