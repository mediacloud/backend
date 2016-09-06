package MediaWords::Crawler::Handler;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

Mediawords::Crawler::Handler - process the http response from the fetcher - parse feeds, add new stories, add content

=head1 SYNOPSIS

    # this is a simplified version of the code used in the crawler to invoke the handler

    # get pending $download from somewhere
    my $fetcher = MediaWords::Crawler::Fetcher->new();
    my $response = $fetcher->fetch_download( $db, $download );

    # handle $download
    my $handler = MediaWords::Crawler->Handler->new();
    $handler->handler_response( $response );

=head1 DESCRIPTION

The handler is responsible for accepting the http response from the fetcher, performing whatever logic is required
by the system for the given download type, and storing successful response content in content store.

For all downloads, the handle stores the content of successful downloads in the content store system (either a local
posgres table or, on the production media cloud system, in amazon s3).

If the download has a type of 'feed', the handler parses the feed and looks for the urls of any new stories.  A story
is considered new if the url or guid is not already in the database for the given media source and if the story
title is unique for the media source for the calendar week.  If the story is new, a story is added to the stories
table and a download with a type of 'pending' is added to the downloads table.

For 'feed' downloads, after parsing the feed but before checking for new stories, we generate a checksum of the sorted
urls of the feed.  We check that checksum against the last_checksum value of the feed, and if the value is the same, we
store '(redundant feed)' as the content of the feed and do not check for new stories.  This check prevents frequent
storage of redundant feed content and also avoids the considerable processing time required to check individual
urls for new stories.

If the download has a type of 'content', the handler merely stores the content for the given story and then queues
an extraction job for the download.

If the response is an error and the status is a '503' or a '500 read timeout', the handler queues the download for
another attempt (up to a max of 5 retries) with a backoff timing starting at one hour.  If the response is an error
with another status, the 'state' of the download is set to 'error'.

=cut

use strict;
use warnings;

use Data::Dumper;
use Date::Parse;
use Encode;
use Readonly;

use List::Util qw (max maxstr);

use Feed::Scrape::MediaWords;
use MediaWords::Crawler::Handler::Content;
use MediaWords::Crawler::Handler::Feed;

# CONSTANTS

# max number of times to try a page after a 5xx error
Readonly my $MAX_5XX_RETRIES => 10;

=head1 METHODS

=head2 new()

Create new download handler object

=cut

sub new($;$)
{
    my ( $class, $args ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->{ extract_in_process } = $args->{ extract_in_process } // 0;

    return $self;
}

# chop out the content if we don't allow the content type
sub _restrict_content_type
{
    my ( $self, $response ) = @_;

    if ( $response->content_type =~ m~text|html|xml|rss|atom~i )
    {
        return;
    }

    $response->content( '(unsupported content type)' );
}

=head2 _handle_error( $db, $download, $response )

Deal with any errors returned by the fetcher response.  If the error status looks like something that the site
could recover from (503, 500 timeout), queue another time out using back off timing.  If we don't recognize the
status as something we can recover from or if we have exceeded the max retries, set the 'state' of the download
to 'error' and set the 'error_messsage' to describe the error.

=cut

sub _handle_error($$$$)
{
    my ( $self, $db, $download, $response ) = @_;

    return 0 if ( $response->is_success );

    my $error_num = 1;
    if ( my $error = $download->{ error_message } )
    {
        $error_num = ( $error =~ /\[error_num: (\d+)\]$/ ) ? $1 + 1 : 1;
    }

    my $enc_error_message = encode( 'utf8', $response->status_line . "\n[error_num: $error_num]" );

    if ( ( $response->status_line =~ /^(503|500 read timeout)/ ) && ( $error_num <= $MAX_5XX_RETRIES ) )
    {
        my $interval = "$error_num hours";

        $db->query( <<END, $interval, $enc_error_message, $download->{ downloads_id }, );
update downloads set
        state = 'pending',
        download_time = now() + \$1::interval ,
        error_message = \$2
    where downloads_id = \$3
END
    }
    else
    {
        $db->query( <<END, $enc_error_message, $download->{ downloads_id } );
UPDATE downloads
SET state = 'error',
    error_message = ?
WHERE downloads_id = ?
END
    }

    return 1;
}

=head2 handle_response( $db, $download, $response )

If the response is an error, call _handle_error() to handle the error and return. Otherwise, store the $response content in
the MediaWords::DBI::Downloads content store, associated with the download. If the download is a feed, parse the feed
for new stories, add those stories to the db, and queue a download for each. If the download is a content download,
queue extraction of the story.

More details in the DESCRIPTION above and in MediaWords::Crawler::Handler::Feed, which handles the feed downloads.

=cut

sub handle_response($$$$)
{
    my ( $self, $db, $download, $response ) = @_;

    my $downloads_id  = $download->{ downloads_id };
    my $download_url  = $download->{ url };
    my $download_type = $download->{ type };

    DEBUG "Handling download $downloads_id ($download_url)...";

    if ( $self->_handle_error( $db, $download, $response ) )
    {
        DEBUG "Download $downloads_id errored: " . $response->decoded_content;
        return;
    }

    $self->_restrict_content_type( $response );

    $db->query( <<END, $download->{ url }, $download->{ downloads_id } );
update downloads set url = ? where downloads_id = ?
END

    my $download_handler;
    if ( $download_type eq 'feed' )
    {
        $download_handler = MediaWords::Crawler::Handler::Feed->new();
    }
    elsif ( $download_type eq 'content' )
    {
        $download_handler = MediaWords::Crawler::Handler::Content->new();
    }
    else
    {
        die "Unknown download type '$download_type' of download $downloads_id\n";
    }

    my $story_ids_to_extract;
    eval { $story_ids_to_extract = $download_handler->handle_download( $db, $download, $response->decoded_content ); };
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
        my $args = { stories_id => $stories_id };

        if ( $self->{ extract_in_process } )
        {
            DEBUG "Extracting story $stories_id for download $downloads_id in process...";
            MediaWords::Job::ExtractAndVector->run( $args );
        }
        else
        {
            TRACE "Adding story $stories_id for download $downloads_id to extraction queue...";
            MediaWords::Job::ExtractAndVector->add_to_queue( $args );
        }
    }

    DEBUG "Handled download $downloads_id ($download_url).";
}

1;
