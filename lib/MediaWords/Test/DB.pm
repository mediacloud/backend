package MediaWords::Test::DB;

# database utility functions for testing.  includes functionality to run tests on a temporary db

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use File::Path;

use DBIx::Simple::MediaWords;
use MediaWords::DB;
use MediaWords::DBI::Auth;
use MediaWords::Pg::Schema;
use MediaWords::Util::Config;
use MediaWords::Util::URL;

# run the given function on a temporary, clean database
sub test_on_test_database
{
    my ( $sub ) = @_;

    MediaWords::Pg::Schema::recreate_db( 'test' );

    my $db = MediaWords::DB::connect_to_db( 'test' );

    my $previous_force_using_test_db_value = $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE };
    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = 1;

    eval { $sub->( $db ); };

    $ENV{ MEDIAWORDS_FORCE_USING_TEST_DATABASE } = $previous_force_using_test_db_value;

    if ( $@ )
    {
        die( $@ );
    }

    if ( $db )
    {
        $db->disconnect();
    }
}

sub create_download_for_feed
{
    my ( $feed, $dbs ) = @_;

    my $priority = 0;
    if ( !$feed->{ last_attempted_download_time } )
    {
        $priority = 10;
    }

    my $host     = MediaWords::Util::URL::get_url_host( $feed->{ url } );
    my $download = $dbs->create(
        'downloads',
        {
            feeds_id      => $feed->{ feeds_id },
            url           => $feed->{ url },
            host          => $host,
            type          => 'feed',
            sequence      => 1,
            state         => 'pending',
            priority      => $priority,
            download_time => 'now()',
            extracted     => 'f'
        }
    );

    return $download;
}

# create test medium with a simple label
sub create_test_medium
{
    my ( $db, $label ) = @_;

    return $db->create(
        'media',
        {
            name      => $label,
            url       => "http://media.test/$label",
            moderated => 't',
        }
    );
}

# create test feed with a simple label belonging to $medium
sub create_test_feed
{
    my ( $db, $label, $medium ) = @_;

    return $db->create(
        'feeds',
        {
            name     => $label,
            url      => "http://feed.test/$label",
            media_id => $medium->{ media_id }
        }
    );
}

# create test story with a simple label belonging to $feed
sub create_test_story
{
    my ( $db, $label, $feed ) = @_;

    my $story = $db->create(
        'stories',
        {
            media_id      => $feed->{ media_id },
            url           => "http://story/$label",
            guid          => "guid://story/$label",
            title         => "story $label",
            description   => "description $label",
            publish_date  => \'now() - interval \'100000 seconds\'',
            collect_date  => \'now() - interval \'200000 seconds\'',
            full_text_rss => 't'
        }
    );

    $db->query( <<END, $feed->{ feeds_id }, $story->{ stories_id } );
insert into feeds_stories_map ( feeds_id, stories_id ) values ( ?, ? )
END

    return $story;
}

# create structure of media, feeds, and stories from hash.
# given a hash in this form:
# my $data = {
#     A => {
#         B => [ 1, 2 ],
#         C => [ 4 ]
#     },
# };
# returns the list of media sources created, with a feeds field on each medium and
# a stories field on each field, all referenced by the given labels, in this form:
# { A => {
#     $medium_a_hash,
#     feeds => {
#         B => {
#             $feed_b_hash,
#             stories => {
#                 1 => { $story_1_hash },
#                 2 => { $story_2_hash },
#             }
#         }
#     },
#   B => { $feed_b_hash },
#   1 => { $story_1_hash },
#   2 => { $story_2_hash }
# }
#
# so, for example, story 2 can be accessed in the return value as either
#   $data->{ A }->{ feeds }->{ B }->{ stories }->{ 2 }
# or simply as
#   $data->{ 2 }
sub create_test_story_stack
{
    my ( $db, $data ) = @_;

    die( "invalid media data format" ) unless ( ref( $data ) eq 'HASH' );

    my $media = {};
    while ( my ( $medium_label, $feeds ) = each( %{ $data } ) )
    {
        die( "$medium_label medium label already used in story stack" ) if ( $media->{ $medium_label } );
        my $medium = create_test_medium( $db, $medium_label );
        $media->{ $medium_label } = $medium;

        die( "invalid feeds data format" ) unless ( ref( $feeds ) eq 'HASH' );

        while ( my ( $feed_label, $story_labels ) = each( %{ $feeds } ) )
        {
            die( "$feed_label feed label already used in story stack" ) if ( $media->{ $feed_label } );
            my $feed = create_test_feed( $db, $feed_label, $medium );
            $medium->{ feeds }->{ $feed_label } = $feed;
            $media->{ $feed_label } = $feed;

            die( "invalid stories data format" ) unless ( ref( $story_labels ) eq 'ARRAY' );

            for my $story_label ( @{ $story_labels } )
            {
                die( "$story_label story label already used in story stack" ) if ( $media->{ $story_label } );
                my $story = create_test_story( $db, $story_label, $feed );
                $feed->{ stories }->{ $story_label } = $story;
                $media->{ $story_label } = $story;
            }
        }
    }

    # Create a user for temporary databases
    sub create_test_user
    {
        my $db = shift;

        my $add_user_error_message =
          MediaWords::DBI::Auth::add_user_or_return_error_message( $db, 'jdoe@cyber.law.harvard.edu', 'John Doe', '', [ 1 ],
            1, 'testtest', 'testtest', 1, 1000, 1000 );

        my $api_key = $db->query( "select api_token from auth_users where email =\'jdoe\@cyber.law.harvard.edu\'" )->hash;

        return $api_key->{ api_token };

    }

    return $media;
}

# create test topic with a simple label.  create associated topic_dates and topic_tag_set rows as well
sub create_test_topic($$)
{
    my ( $db, $label ) = @_;

    my $topic_tag_set = $db->create( 'tag_sets', { name => "topic $label" } );

    my $topic = $db->create(
        'topics',
        {
            name                => $label,
            description         => $label,
            pattern             => $label,
            solr_seed_query     => $label,
            solr_seed_query_run => 't',
            topic_tag_sets_id   => $topic_tag_set->{ topic_tag_sets_id }
        }
    );

    $db->create(
        'topic_dates',
        {
            topics_id  => $topic->{ topics_id },
            start_date => '2016-01-01',
            end_date   => '2016-03-01',
            boundary   => 't'
        }
    );

    return $topic;
}

1;
