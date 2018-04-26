package MediaWords::Crawler::Download::Feed::Superglue;

#
# Handler for 'superglue' feed downloads
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::Crawler::Download::DefaultFetcher', 'MediaWords::Crawler::Download::Feed::FeedHandler';

use MediaWords::Crawler::Engine;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Feeds;
use MediaWords::DBI::Stories;

use Data::Dumper;
use Date::Parse;
use Encode;
use MediaWords::Feed::Parse;
use Readonly;

# parse the feed content; create a story hash for each parsed story; check for a new url since the last
# feed download; if there is a new url, check whether each story is new, and if so add it to the database and
# ad a pending download for it.
# return new stories that were found in the feed.
sub add_stories_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $downloads_id  = $download->{ downloads_id };
    my $download_time = $download->{ download_time };

    my $media_id = MediaWords::DBI::Downloads::get_media_id( $db, $download );

    Readonly my $skip_preprocessing => 1;
    my $feed = MediaWords::Feed::Parse::parse_feed( $decoded_content, $skip_preprocessing );
    unless ( $feed )
    {
        die "Unable to parse Superglue feed";
    }

    my $stories           = [];
    my $superglue_stories = [];    # Additional Superglue data
    foreach my $item ( @{ $feed->items() } )
    {
        my ( $title, $video_url, $transcript, $guid, $publish_date, $thumbnail_url, $segment_duration );
        eval {
            # As this is a private feed, require all fields to be present
            $title        = $item->title()            or die "<title> not set";
            $video_url    = $item->link()             or die "<link> not set";
            $transcript   = $item->description()      or die "<description> not set";
            $guid         = $item->guid()             or die "<guid> not set";
            $publish_date = $item->publish_date_sql() or die "<pubDate> not set";

            $thumbnail_url    = $item->get( 'enclosure@url' )    // '';
            $segment_duration = $item->get( 'segment:duration' ) // '';
        };
        if ( $@ )
        {
            LOGCONFESS "Failed to add Superglue stories from download $downloads_id, item " . Dumper( $item ) . ": $@";
        }

        # Remove special markings to extract text correctly:

        # ">>>" at the beginning of text probably means "new subject"
        $transcript =~ s/^>>>\s//gs;
        $transcript =~ s/^>>\s//gs;    # typo by the transcriber?

        # ">>" probably means "new speaker"
        $transcript =~ s/\s>>\s/\n\n/gs;
        $transcript =~ s/\s>>>\s/\n\n/gs;    # typo by the transcriber?

        my $story = {
            url          => $guid,           # Video URL is not public by request
            guid         => $guid,
            media_id     => $media_id,
            publish_date => $publish_date,
            title        => $title,
            description  => $transcript,

            # Superglue feeds are full text RSS
            full_text_rss => 't',

            # 'language' will be set by process_extracted_story()
        };
        my $superglue_story = {
            video_url        => $video_url,
            thumbnail_url    => $thumbnail_url,
            segment_duration => $segment_duration,
        };

        push( @{ $stories },           $story );
        push( @{ $superglue_stories }, $superglue_story );
    }

    if ( MediaWords::DBI::Feeds::stories_checksum_matches_feed( $db, $download->{ feeds_id }, $stories ) )
    {
        return [];
    }

    my $added_stories_ids = [];
    for ( my $x = 0 ; $x < scalar( @{ $stories } ) ; ++$x )
    {
        my $story           = $stories->[ $x ];
        my $superglue_story = $superglue_stories->[ $x ];

        unless ( MediaWords::DBI::Stories::is_new( $db, $story ) )
        {
            next;
        }

        my $added_story = MediaWords::DBI::Stories::add_story( $db, $story, $download->{ feeds_id } );
        my $added_stories_id = $added_story->{ stories_id };

        # Fill "story_sentences", set story language etc.
        my $extractor_args = MediaWords::DBI::Stories::ExtractorArguments->new(
            {
                # Readability not used because plain text feed provided
                no_tag_extractor_version => 1
            }
        );
        MediaWords::DBI::Stories::process_extracted_story( $db, $added_story, $extractor_args );

        # Record metadata
        $db->create(
            'stories_superglue_metadata',
            {
                'stories_id'       => $added_stories_id,
                'video_url'        => $superglue_story->{ video_url },
                'thumbnail_url'    => $superglue_story->{ thumbnail_url },
                'segment_duration' => $superglue_story->{ segment_duration },
            }
        );

        push( @{ $added_stories_ids }, $added_stories_id );
    }

    return $added_stories_ids;
}

sub return_stories_to_be_extracted_from_feed($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    # Superglue feeds are full text RSS so we don't have to extract anything
    return [];
}

1;
