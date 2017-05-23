package MediaWords::Test::DB;

# database utility functions for testing.  includes functionality to run tests on a temporary db

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.test.db' );

use File::Path;
use Readonly;
use Text::Lorem::More;

use MediaWords::DB;
use MediaWords::DBI::Auth;
use MediaWords::DBI::Downloads;
use MediaWords::Job::ExtractAndVector;
use MediaWords::DB::Schema;
use MediaWords::Util::Config;
use MediaWords::Util::URL;

# run the given function on a temporary, clean database
sub test_on_test_database
{
    my ( $sub ) = @_;

    MediaWords::DB::Schema::recreate_db( 'test' );

    my $db = MediaWords::DB::connect_to_db( 'test' );

    force_using_test_database();

    eval { $sub->( $db ); };

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
            name         => $label,
            url          => "http://media.test/$label",
            moderated    => 't',
            is_monitored => 't',
            public_notes => "$label public notes",
            editor_notes => "$label editor notes"
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
            url           => "http://story.test/$label",
            guid          => "guid://story.test/$label",
            title         => "story $label",
            description   => "description $label",
            publish_date  => '2016-10-15 08:00:00',
            collect_date  => '2016-10-15 10:00:00',
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

    return $media;
}

# call create_test_story_stack with $num_media, num_feeds_per_medium, $num_stories_per_feed instead of
# explicit hash as described above
sub create_test_story_stack_numerated($$$$;$)
{
    my ( $db, $num_media, $num_feeds_per_medium, $num_stories_per_feed, $label ) = @_;

    my $feed_index  = 0;
    my $story_index = 0;

    $label ||= 'test';

    my $def = {};
    for my $i ( 0 .. $num_media - 1 )
    {
        my $feeds = {};
        $def->{ "media_${ label }_${ i }" } = $feeds;

        for my $j ( 0 .. $num_feeds_per_medium - 1 )
        {
            $feeds->{ "feed_${ label }_" . $feed_index++ } =
              [ map { "story_" . $story_index++ } ( 0 .. $num_stories_per_feed - 1 ) ];
        }
    }

    return create_test_story_stack( $db, $def );
}

# generated 1 - 10 paragraphs of 1 - 5 sentences of ipsem lorem.
sub get_test_content
{
    my $lorem = Text::Lorem::More->new();

    my $num_paragraphs = int( rand( 10 ) + 1 );

    my $paragraphs = [];

    for my $i ( 1 .. $num_paragraphs )
    {
        my $text = $lorem->sentences( int( rand( 5 ) + 1 ) );
        push( @{ $paragraphs }, $text );
    }

    my $content = join( "\n\n", map { "<p>\n$_\n</p>" } @{ $paragraphs } );

    return $content;
}

# adds a 'download' and a 'content' field to each story in the test story stack.  stores the content in the download
# store.  generates the content using get_test_content()
sub add_content_to_test_story($$$)
{
    my ( $db, $story, $feed ) = @_;

    my $content = get_test_content();

    if ( $story->{ full_text_rss } )
    {
        $story->{ full_text_rss } = 0;
        $db->update_by_id( 'stories', $story->{ stories_id }, { full_text_rss => 'f' } );
    }

    my $host     = MediaWords::Util::URL::get_url_host( $feed->{ url } );
    my $download = $db->create(
        'downloads',
        {
            feeds_id      => $feed->{ feeds_id },
            url           => $story->{ url },
            host          => $host,
            type          => 'content',
            sequence      => 1,
            state         => 'fetching',
            priority      => 1,
            download_time => 'now()',
            extracted     => 'f',
            stories_id    => $story->{ stories_id }
        }
    );

    $download = MediaWords::DBI::Downloads::store_content( $db, $download, \$content );

    $story->{ download } = $download;
    $story->{ content }  = $content;

    MediaWords::Job::ExtractAndVector->run( { stories_id => $story->{ stories_id } } );

    $story->{ download_text } = $db->query( <<SQL, $download->{ downloads_id } )->hash;
select * from download_texts where downloads_id = ?
SQL

    die( "Unable to find download_text" ) unless ( $story->{ download_text } );
}

# add a download and store its content for each story in the test story stack as returned from create_test_story_stack.
# also extract and vector each download.
sub add_content_to_test_story_stack($$)
{
    my ( $db, $story_stack ) = @_;

    DEBUG( "adding content to test story stack ..." );

    for my $medium ( values( %{ $story_stack } ) )
    {
        for my $feed ( values( %{ $medium->{ feeds } } ) )
        {
            for my $story ( values( %{ $feed->{ stories } } ) )
            {
                add_content_to_test_story( $db, $story, $feed );
            }
        }
    }
}

# Create a user for temporary databases
sub create_test_user($$)
{
    my ( $db, $label ) = @_;

    my $email = $label . '@em.ail';

    eval {
        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email                        => $email,
            full_name                    => $label,
            notes                        => '',
            role_ids                     => [ 1 ],
            active                       => 1,
            password                     => 'testtest',
            password_repeat              => 'testtest',
            activation_url               => '',           # user is active, no need for activation URL
            weekly_requests_limit        => 1000,
            weekly_requested_items_limit => 1000,
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    if ( $@ )
    {
        LOGCONFESS "Adding new user failed: $@";
    }

    my $user_info = MediaWords::DBI::Auth::Profile::user_info( $db, $email );
    my $api_key = $user_info->global_api_key();

    return $api_key;
}

# create test topic with a simple label.
sub create_test_topic($$)
{
    my ( $db, $label ) = @_;

    my $topic = $db->create(
        'topics',
        {
            name                => $label,
            description         => $label,
            pattern             => $label,
            solr_seed_query     => $label,
            solr_seed_query_run => 't',
            start_date          => '2016-01-01',
            end_date            => '2016-03-01',
            job_queue           => 'mc',
            max_stories         => 100_000
        }
    );

    return $topic;
}

1;
