package MediaWords::Crawler::Download::Feed::WebPage;

#
# Handler for 'web_page' feed downloads
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::Crawler::Download::DefaultFetcher', 'MediaWords::Crawler::Download::Feed::FeedHandler';

use MediaWords::Util::ParseHTML;
use MediaWords::Util::SQL;

use Readonly;

# handle feeds of type 'web_page' by just creating a story to associate with the content.  web page feeds are feeds
# that consist of a web page that we download once a week and add as a story.
sub add_stories_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $feeds_id = $download->{ feeds_id };

    my $feed = $db->find_by_id( 'feeds', $feeds_id );

    my $title = MediaWords::Util::ParseHTML::html_title( $decoded_content, '(no title)' );
    my $guid = substr( time . ":" . $download->{ url }, 0, 1024 );

    my $new_story = {
        url          => $download->{ url },
        guid         => $guid,
        media_id     => $feed->{ media_id },
        publish_date => MediaWords::Util::SQL::sql_now,
        title        => $title,
    };

    Readonly my $skip_checking_if_new => 1;
    my $story = MediaWords::DBI::Stories::add_story( $db, $new_story, $feeds_id, $skip_checking_if_new );
    unless ( defined $story )
    {
        LOGCONFESS "Failed to add story " . Dumper( $new_story );
    }

    $db->query(
        <<SQL,
        UPDATE downloads
        SET stories_id = ?,
            type = 'content'
        WHERE downloads_id = ?
SQL
        $story->{ stories_id },
        $download->{ downloads_id }
    );

    # A webpage that was just fetched is also a story
    my $story_ids = [ $story->{ stories_id } ];
    return $story_ids;
}

# Extract the web_page feed (story) that was just downloaded
sub return_stories_to_be_extracted_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    # Download row might have been changed by add_stories_from_feed()
    $download = $db->find_by_id( 'downloads', $download->{ downloads_id } );

    # Extract web page download that was just fetched
    my $stories_to_extract = [ $download->{ stories_id } ];
    return $stories_to_extract;
}

1;
