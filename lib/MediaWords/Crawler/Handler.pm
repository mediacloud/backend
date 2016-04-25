package MediaWords::Crawler::Handler;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

Mediawords::Crawler::Handler - process the http response from the fetcher - parse feeds, add new stories, add content

=head1 SYNOPSIS

    # this is a simplified version of the code used in the crawler to invoke the handler

    my $crawler = MediaWords::Crawler::Engine->new();

    my $fetcher = MediaWords::Crawler::Fetcher->new( $crawler );

    # get pending $download from somewhere

    my $response = $fetcher->fetch_download( $download );

    my $handler = MediaWords::Crawler->Handler->new( $engine );

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
use FindBin;
use Readonly;
use URI::Split;
use if $] < 5.014, Switch => 'Perl6';
use if $] >= 5.014, feature => 'switch';
use Carp;

use List::Util qw (max maxstr);

use Feed::Scrape::MediaWords;
use MediaWords::Crawler::FeedHandler;
use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::GearmanFunction::ExtractAndVector;
use MediaWords::Util::Config;
use MediaWords::Util::SQL;

# CONSTANTS

# max number of pages the handler will download for a single story
Readonly my $MAX_PAGES => 10;

# max number of times to try a page after a 5xx error
Readonly my $MAX_5XX_RETRIES => 10;

=head1 METHODS

=head2 new( $engine )

Create new handler object

=cut

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine( $engine );

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

# return 1 if medium->{ use_pager } is null or true and 0 otherwise
sub _use_pager
{
    my ( $medium ) = @_;

    return 1 if ( !defined( $medium->{ use_pager } ) || $medium->{ use_pager } );

    return 0;
}

# we keep track of a use_pager field in media to determine whether we should try paging stories within a given media
# souce.  We assume that we don't need to keep trying paging stories if we have tried but failed to find  next pages in
# 100 stories in that media source in a row.
#
# If use_pager is already set, do nothing.  Otherwise, if next_page_url is true, set use_pager to true.  Otherwise, if
# there are less than 100 unpaged_stories, increment unpaged_stories.  If there are at least 100 unpaged_stories, set
# use_pager to false.
sub _set_use_pager
{
    my ( $dbs, $medium, $next_page_url ) = @_;

    return if ( defined( $medium->{ use_pager } ) );

    if ( $next_page_url )
    {
        $dbs->query( "update media set use_pager = 't' where media_id = ?", $medium->{ media_id } );
    }
    elsif ( !defined( $medium->{ unpaged_stories } ) )
    {
        $dbs->query( "update media set unpaged_stories = 1 where media_id = ?", $medium->{ media_id } );
    }
    elsif ( $medium->{ unpaged_stories } < 100 )
    {
        $dbs->query( "update media set unpaged_stories = unpaged_stories + 1 where media_id = ?", $medium->{ media_id } );
    }
    else
    {
        $dbs->query( "update media set use_pager = 'f' where media_id = ?", $medium->{ media_id } );
    }
}

# if _use_pager( $medium ) returns true, call MediaWords::Crawler::Pager::get_next_page_url on the download
sub _call_pager
{
    my ( $self, $dbs, $download ) = @_;
    my $content = \$_[ 3 ];

    my $medium = $dbs->query( <<END, $download->{ feeds_id } )->hash;
select * from media m where media_id in ( select media_id from feeds where feeds_id = ? );
END

    return unless ( _use_pager( $medium ) );

    if ( $download->{ sequence } > $MAX_PAGES )
    {
        DEBUG "reached max pages ($MAX_PAGES) for url '$download->{ url }'";
        return;
    }

    if ( $dbs->query( "SELECT * from downloads where parent = ? ", $download->{ downloads_id } )->hash )
    {
        return;
    }

    my $ret;

    my $validate_url = sub { !$dbs->query( "select 1 from downloads where url = ?", $_[ 0 ] ) };

    my $next_page_url = MediaWords::Crawler::Pager::get_next_page_url( $validate_url, $download->{ url }, $content );

    if ( $next_page_url )
    {
        DEBUG "next page: $next_page_url\nprev page: $download->{ url }";

        $ret = $dbs->create(
            'downloads',
            {
                feeds_id   => $download->{ feeds_id },
                stories_id => $download->{ stories_id },
                parent     => $download->{ downloads_id },
                url        => $next_page_url,
                host       => lc( ( URI::Split::uri_split( $next_page_url ) )[ 1 ] ),
                type       => 'content',
                sequence   => $download->{ sequence } + 1,
                state      => 'pending',
                priority   => $download->{ priority } + 1,
                extracted  => 'f'
            }
        );
    }

    _set_use_pager( $dbs, $medium, $next_page_url );
    return $ret;
}

# queue a gearman extraction job for the story
sub _queue_story_extraction($$)
{
    my ( $self, $download ) = @_;

    my $db             = $self->engine->dbs;
    my $fetcher_number = $self->engine->fetcher_number;

    DEBUG "fetcher $fetcher_number starting extraction for download " . $download->{ downloads_id };

    MediaWords::GearmanFunction::ExtractAndVector->extract_for_crawler( $db, { stories_id => $download->{ stories_id } },
        $fetcher_number );
}

# call the pager module on the download and queue the story for extraction if this are no other pages for the story
sub _process_content
{
    my ( $self, $dbs, $download, $response ) = @_;

    DEBUG "fetcher " . $self->engine->fetcher_number . " starting _process_content for  " . $download->{ downloads_id };

    my $next_page = $self->_call_pager( $dbs, $download, $response->decoded_content );

    if ( !$next_page )
    {
        $self->_queue_story_extraction( $download );
    }
    else
    {
        DEBUG "fetcher skipping extraction download " . $download->{ downloads_id } . " until all pages are available";
    }

    DEBUG "fetcher " . $self->engine->fetcher_number . " finished _process_content for  " . $download->{ downloads_id };
}

=head2 handle_error( $download, $response )

Deal with any errors returned by the fetcher response.  If the error status looks like something that the site
could recover from (503, 500 timeout), queue another time out using back off timing.  If we don't recognize the
status as something we can recover from or if we have exceeded the max retries, set the 'state' of the download
to 'error' and set the 'error_messsage' to describe the error.

=cut

sub handle_error
{
    my ( $self, $download, $response ) = @_;

    return 0 if ( $response->is_success );

    my $dbs = $self->engine->dbs;

    my $error_num = 1;
    if ( my $error = $download->{ error_message } )
    {
        $error_num = ( $error =~ /\[error_num: (\d+)\]$/ ) ? $1 + 1 : 1;
    }

    my $enc_error_message = encode( 'utf8', $response->status_line . "\n[error_num: $error_num]" );

    if ( ( $response->status_line =~ /^(503|500 read timeout)/ ) && ( $error_num <= $MAX_5XX_RETRIES ) )
    {
        my $interval = "$error_num hours";

        $dbs->query( <<END, $interval, $enc_error_message, $download->{ downloads_id }, );
update downloads set
        state = 'pending',
        download_time = now() + \$1::interval ,
        error_message = \$2
    where downloads_id = \$3
END
    }
    else
    {
        $dbs->query( <<END, $enc_error_message, $download->{ downloads_id } );
UPDATE downloads
SET state = 'error',
    error_message = ?,
    -- reset the file status in case it's one of the "missing" downloads:
    file_status = DEFAULT
WHERE downloads_id = ?
END
    }

    return 1;
}

=head2 handle_response( $response )

If the response is an error, call handle_error to handle the error and return. Otherwise, store the $response content in
the MediaWords::DBI::Downloads content store, associated with the download. If the download is a feed, parse the feed
for new stories, add those stories to the db, and queue a download for each. If the download is a content download,
queue extraction of the story.

More details in the DESCRIPTION above and in MediaWords::Crawler::FeedHandler, which handles the feed downloads.

=cut

sub handle_response
{
    my ( $self, $download, $response ) = @_;

    if ( defined( $self->engine->fetcher_number ) )
    {
        DEBUG "fetcher " . $self->engine->fetcher_number . " starting handle response: " . $download->{ url };
    }

    my $dbs = $self->engine->dbs;

    return if ( $self->handle_error( $download, $response ) );

    $self->_restrict_content_type( $response );

    $dbs->query( <<END, $download->{ url }, $download->{ downloads_id } );
update downloads set url = ? where downloads_id = ?
END

    my $download_type = $download->{ type };

    if ( $download_type eq 'feed' )
    {
        my $config = MediaWords::Util::Config::get_config;
        if (   ( $config->{ mediawords }->{ do_not_process_feeds } )
            && ( $config->{ mediawords }->{ do_not_process_feeds } eq 'yes' ) )
        {
            MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->decoded_content );
            WARN "DO NOT PROCESS FEEDS";
            $self->engine->dbs->update_by_id(
                'downloads',
                $download->{ downloads_id },
                { state => 'feed_error', error_message => 'do_not_process_feeds' }
            );
        }
        else
        {
            MediaWords::Crawler::FeedHandler::handle_feed_content( $dbs, $download, $response->decoded_content );
        }

    }
    elsif ( $download_type eq 'content' )
    {
        MediaWords::DBI::Downloads::store_content( $dbs, $download, \$response->decoded_content );
        $self->_process_content( $dbs, $download, $response );

    }
    else
    {
        die "Unknown download type " . $download->{ type }, "\n";

    }

    if ( defined( $self->engine->fetcher_number ) )
    {
        DEBUG "fetcher " . $self->engine->fetcher_number . " completed handle response: " . $download->{ url };
    }
}

=head2 engine

getset engine - calling crawler engine

=cut

sub engine
{
    if ( $_[ 1 ] )
    {
        $_[ 0 ]->{ engine } = $_[ 1 ];
    }

    return $_[ 0 ]->{ engine };
}

1;
