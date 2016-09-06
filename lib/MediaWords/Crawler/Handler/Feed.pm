package MediaWords::Crawler::Handler::Feed;

#
# Handler for 'feed' downloads
#

=head1 NAME

MediaWords::Crawler::Handler::Feed - implementation details of the feed handling called from MediaWords::Crawler::Handler

=head1 DESCRIPTION

The feed handler parses the feed and looks for the urls of any new stories.  A story is considered new if the url or
guid is not already in the database for the given media source and if the story title is unique for the media source for
the calendar week.  If the story is new, a story is added to the stories table and a download with a type of 'pending'
is added to the downloads table.

After parsing the feed but before checking for new stories, we generate a checksum of the sorted urls of the feed.  We
check that checksum against the last_checksum value of the feed, and if the value is the same, we store '(redundant
feed)' as the content of the feed and do not check for new stories.  This check prevents frequent storage of redundant
feed content and also avoids the considerable processing time required to check individual urls for new stories.

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::Crawler::Handler::AbstractHandler';

use MediaWords::Crawler::Handler::Feed::Syndicated;
use MediaWords::Crawler::Handler::Feed::WebPage;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;

use Readonly;

=head1 METHODS

=cut

=head2 _handle_feed_content( $self, $db, $download, $decoded_content )

For web page feeds, just store the downloaded content as a story and queue the story for extraction.  For syndicated
feeds, create new stories for any new story urls in the feed content.  More details in the DESCRIPTION above.

Also store the content of the feed for the download and set the feed.last_successful_download_time to now.

=cut

sub _handle_feed_content($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $feed = $db->find_by_id( 'feeds', $download->{ feeds_id } );
    my $feed_type = $feed->{ feed_type };

    my $story_ids_to_extract = [];
    my $num_new_stories      = 0;
    eval {
        my $feed_handler;

        if ( $feed_type eq 'syndicated' )
        {
            $feed_handler = MediaWords::Crawler::Handler::Feed::Syndicated->new();
        }
        elsif ( $feed_type eq 'web_page' )
        {
            $feed_handler = MediaWords::Crawler::Handler::Feed::WebPage->new();
        }
        else
        {
            die "Unknown feed type '$feed_type'";
        }

        $story_ids_to_extract = $feed_handler->handle_download( $db, $download, $decoded_content );
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

    if ( scalar( @{ $story_ids_to_extract } ) > 0 )
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
        $decoded_content = '(redundant feed)';
    }

    MediaWords::DBI::Downloads::store_content( $db, $download, \$decoded_content );

    return $story_ids_to_extract;
}

# Returns story IDs to extract
sub handle_download($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $downloads_id = $download->{ downloads_id };

    DEBUG "Processing feed download $downloads_id...";

    my $story_ids_to_extract = [];

    my $config = MediaWords::Util::Config::get_config;
    if (   ( $config->{ mediawords }->{ do_not_process_feeds } )
        && ( $config->{ mediawords }->{ do_not_process_feeds } eq 'yes' ) )
    {
        MediaWords::DBI::Downloads::store_content( $db, $download, \$decoded_content );
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
        $story_ids_to_extract = $self->_handle_feed_content( $db, $download, $decoded_content );
    }

    DEBUG "Done processing feed download $downloads_id";

    return $story_ids_to_extract;
}

1;
