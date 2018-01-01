package MediaWords::Crawler::Download::DefaultHandler;

#
# Default response handler implementation
#
# The response handler filters out errors, passes the raw response data to the
# download handler and adds returned story IDs to the extraction queue.
# Download storage is being done in a specific download handler, not the
# response handler.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;
with 'MediaWords::Crawler::HandlerRole';

use MediaWords::JobManager::Job;

# Handle download that was just fetched by preprocessing and storing it
#
# Returns arrayref of story IDs to be extracted, for example:
#
# * 'content' downloads return an arrayref with a single story ID for the
#   content download
# * 'feed/syndicated' downloads return an empty arrayref because there's
#   nothing to be extracted from a syndicated feed
# * 'feed/web_page' downloads return an arrayref with a single 'web_page'
#   story to be extracted
requires 'handle_download';

use Encode;
use Readonly;

# CONSTANTS

# max number of times to try a page after a 5xx error
Readonly my $MAX_5XX_RETRIES => 10;

# Deal with any errors returned by the fetcher response. If the error status
# looks like something that the site could recover from (503, 500 timeout),
# queue another time out using back off timing.  If we don't recognize the
# status as something we can recover from or if we have exceeded the max
# retries, set the 'state' of the download to 'error' and set the
# 'error_messsage' to describe the error.
sub _store_failed_download_error_message($$$$)
{
    my ( $self, $db, $download, $response ) = @_;

    if ( $response->is_success )
    {
        die "Download was successful, so nothing to handle.";
    }

    my $error_num = 1;
    if ( my $error = $download->{ error_message } )
    {
        $error_num = ( $error =~ /\[error_num: (\d+)\]$/ ) ? $1 + 1 : 1;
    }

    my $enc_error_message = encode( 'utf8', $response->status_line . "\n[error_num: $error_num]" );

    if ( ( $response->status_line =~ /^(503|500 read timeout)/ ) && ( $error_num <= $MAX_5XX_RETRIES ) )
    {
        $db->query(
            <<SQL,
            UPDATE downloads
            SET state = 'pending',
                download_time = now() + ?::interval,
                error_message = ?
            WHERE downloads_id = ?
SQL
            "$error_num hours", $enc_error_message, $download->{ downloads_id }
        );
    }
    else
    {
        $db->query(
            <<SQL,
            UPDATE downloads
            SET state = 'error',
                error_message = ?
            WHERE downloads_id = ?
SQL
            $enc_error_message, $download->{ downloads_id }
        );
    }
}

sub handle_response($$$$)
{
    my ( $self, $db, $download, $response ) = @_;

    my $downloads_id  = $download->{ downloads_id };
    my $download_url  = $download->{ url };
    my $download_type = $download->{ type };

    DEBUG "Handling download $downloads_id...";
    TRACE "(URL of download $downloads_id which is about to be handled: $download_url)";

    unless ( $response->is_success )
    {
        DEBUG "Download $downloads_id errored: " . $response->decoded_content;
        $self->_store_failed_download_error_message( $db, $download, $response );
        return;
    }

    my $content;
    if ( $response->content_type =~ m~text|html|xml|rss|atom|application/json~i )
    {
        $content = $response->decoded_content;
    }
    else
    {
        $content = '(unsupported content type)';
    }

    $db->query(
        <<SQL,
        UPDATE downloads
        SET url = ?
        WHERE downloads_id = ?
            and url != ?
SQL
        $download->{ url }, $download->{ downloads_id }, $download->{ url }
    );

    my $story_ids_to_extract;
    eval { $story_ids_to_extract = $self->handle_download( $db, $download, $content ); };
    if ( $@ )
    {
        die "Unable to handle download $downloads_id: $@\n";
    }

    unless ( ref( $story_ids_to_extract ) eq ref( [] ) )
    {
        die "Stories to extract should be a hashref (at least an empty one).\n";
    }

    foreach my $stories_id ( @{ $story_ids_to_extract } )
    {
        my $args = { stories_id => $stories_id + 0 };

        TRACE "Adding story $stories_id for download $downloads_id to extraction queue...";
        MediaWords::JobManager::Job::add_to_queue( 'MediaWords::Job::ExtractAndVector', $args );
    }

    DEBUG "Handled download $downloads_id.";
    TRACE "(URL of download $downloads_id which was just handled: $download_url)";
}

1;
