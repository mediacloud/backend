use strict;
use warnings;

use Test::More tests => 2;
use Test::Deep;

use Data::Dumper;

use MediaWords::CommonLibs;
use MediaWords::DBI::Stories;


sub test_attach_story_data_to_stories()
{
    my $stories = [
        {
            'stories_id' => 1,
            'title' => 'Foo',
        },
        {
            'stories_id' => 2,
            'title' => 'Bar',
        },
        {
            'stories_id' => 3,
            'title' => 'Baz',
        },
    ];

    my $story_data = [
        {
            'stories_id' => 1,
            'description' => 'foo foo foo',
        },
        {
            'stories_id' => 2,
            'description' => 'bar bar bar',
        },
        {
            'stories_id' => 3,
            'description' => 'baz baz baz',
        },
    ];

    my $got_stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $story_data );

    my $expected_stories = [
        {
            'stories_id' => 1,
            'title' => 'Foo',
            'description' => 'foo foo foo',
        },
        {
            'stories_id' => 2,
            'title' => 'Bar',
            'description' => 'bar bar bar',
        },
        {
            'stories_id' => 3,
            'title' => 'Baz',
            'description' => 'baz baz baz',
        }
    ];

    is_deeply( $got_stories, $expected_stories, "attach_story_data_to_stories()" );
}

sub test_attach_story_data_to_stories_list_field()
{
    my $stories = [
        {
            'stories_id' => 1,
            'title' => 'Foo',
        },
        {
            'stories_id' => 2,
            'title' => 'Bar',
        },
        {
            'stories_id' => 3,
            'title' => 'Baz',
        },
    ];

    # Run function with multiple inputs to confirm that existing "attached" data
    # doesn't get overwritten

    my $story_data_1 = [
        {
            'stories_id' => 1,
            'description' => 'foo 1',
        },
        {
            'stories_id' => 1,
            'description' => 'foo 2',
        },
        {
            'stories_id' => 2,
            'description' => 'bar 1',
        },
    ];
    my $story_data_2 = [
        {
            'stories_id' => 2,
            'description' => 'bar 2',
        },
        {
            'stories_id' => 3,
            'description' => 'baz 1',
        },
        {
            'stories_id' => 3,
            'description' => 'baz 2',
        },
    ];

    my $got_stories;
    $got_stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $story_data_1, 'attached' );
    $got_stories = MediaWords::DBI::Stories::attach_story_data_to_stories( $stories, $story_data_2, 'attached' );

    my $expected_stories = [
        {
            'stories_id' => 1,
            'title' => 'Foo',
            'attached' => [
                {
                    'description' => 'foo 1',
                    'stories_id' => 1,
                },
                {
                    'description' => 'foo 2',
                    'stories_id' => 1,
                }
            ],
        },
        {
            'stories_id' => 2,
            'title' => 'Bar',
            'attached' => [
                {
                    'stories_id' => 2,
                    'description' => 'bar 1',
                },
                {
                    'stories_id' => 2,
                    'description' => 'bar 2',
                }
            ],
        },
        {
            'stories_id' => 3,
            'title' => 'Baz',
            'attached' => [
                {
                    'stories_id' => 3,
                    'description' => 'baz 1',
                },
                {
                    'stories_id' => 3,
                    'description' => 'baz 2',
                }
            ],
        },
    ];

    is_deeply( $got_stories, $expected_stories, "attach_story_data_to_stories() with list_field" );
}

sub main
{
    test_attach_story_data_to_stories();
    test_attach_story_data_to_stories_list_field();

    done_testing();
}

main();
