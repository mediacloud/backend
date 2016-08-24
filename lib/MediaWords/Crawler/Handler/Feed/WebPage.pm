package MediaWords::Crawler::Handler::Feed::WebPage;

#
# Handler for 'web_page' feed downloads
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::Crawler::Handler::Feed::AbstractFeedHandler';

use MediaWords::Util::HTML;
use MediaWords::Util::SQL;

use Readonly;

# handle feeds of type 'web_page' by just creating a story to associate with the content.  web page feeds are feeds
# that consist of a web page that we download once a week and add as a story.
sub add_new_stories($$$$$)
{
    my ( $self, $db, $download, $decoded_content, $feed ) = @_;

    my $title = MediaWords::Util::HTML::html_title( $decoded_content, '(no title)' );
    my $guid = substr( time . ":" . $download->{ url }, 0, 1024 );

    my $story = $db->create(
        'stories',
        {
            url          => $download->{ url },
            guid         => $guid,
            media_id     => $feed->{ media_id },
            publish_date => MediaWords::Util::SQL::sql_now,
            title        => $title
        }
    );

    $db->query(
        "insert into feeds_stories_map ( feeds_id, stories_id ) values ( ?, ? )",
        $feed->{ feeds_id },
        $story->{ stories_id }
    );

    $db->query(
        "update downloads set stories_id = ?, type = 'content' where downloads_id = ?",
        $story->{ stories_id },
        $download->{ downloads_id }
    );

    $download->{ stories_id } = $story->{ stories_id };

    # Extract web page download that was just fetched
    my $stories_to_extract = [ $download->{ stories_id } ];
    return $stories_to_extract;
}

1;
