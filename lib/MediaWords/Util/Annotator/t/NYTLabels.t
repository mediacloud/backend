use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More tests => 3;
use Test::Differences;
use Test::Deep;
use Test::NoWarnings;

use Data::Dumper;
use Readonly;

use MediaWords::Util::Annotator::NYTLabels;
use MediaWords::Util::ParseJSON;

use MediaWords::Test::HashServer;
use MediaWords::Test::DB;

Readonly my $HTTP_PORT => 8912;

sub _sample_nytlabels_response()
{
    return {
        "allDescriptors" => [
            {
                "label" => "hurricanes and tropical storms",
                "score" => "0.89891",
            },
            {
                "label" => "energy and power",
                "score" => "0.50804"
            }
        ],
        "descriptors3000" => [
            {
                "label" => "hurricanes and tropical storms",
                "score" => "0.82505"
            },
            {
                "label" => "hurricane katrina",
                "score" => "0.17088"
            }
        ],

        # Only "descriptors600" are to be used
        "descriptors600" => [
            {
                # Newlines should be replaced to spaces, string should get trimmed
                "label" => " hurricanes \n and\r\ntropical\n\nstorms   \r\n  \n",
                "score" => "0.92481"
            },
            {
                "label" => "electric light and power",
                "score" => "0.10210"                     # should be skipped due to threshold
            }
        ],

        "descriptorsAndTaxonomies" => [
            {
                "label" => "top/news",
                "score" => "0.82466"
            },
            {
                "label" => "hurricanes and tropical storms",
                "score" => "0.81941"
            }
        ],
        "taxonomies" => [
            {
                "label" => "Top/Features/Travel/Guides/Destinations/Caribbean and Bermuda",
                "score" => "0.83390"
            },
            {
                "label" => "Top/News",
                "score" => "0.77210"
            }
        ]
    };
}

sub test_nytlabels_annotator($)
{
    my $db = shift;

    my $media = $db->create(
        'media',
        {
            name => "test medium",
            url  => "url://test/medium",
        }
    );

    my $story = $db->create(
        'stories',
        {
            media_id      => $media->{ media_id },
            url           => 'url://story/a',
            guid          => 'guid://story/a',
            title         => 'story a',
            description   => 'description a',
            publish_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() ),
            collect_date  => MediaWords::Util::SQL::get_sql_date_from_epoch( time() ),
            full_text_rss => 't'
        }
    );
    my $stories_id = $story->{ stories_id };

    $db->create(
        'story_sentences',
        {
            stories_id      => $stories_id,
            sentence_number => 1,
            sentence        => 'I hope that the NYTLabels annotator is working.',
            media_id        => $media->{ media_id },
            publish_date    => MediaWords::Util::SQL::get_sql_date_from_epoch( time() ),
            language        => 'en'
        }
    );

    my $encoded_json = MediaWords::Util::ParseJSON::encode_json( _sample_nytlabels_response() );

    my $pages = {

        # Mock annotator
        '/predict.json' => {
            callback => sub {
                my ( $request ) = @_;
                my $response = '';
                $response .= "HTTP/1.0 200 OK\r\n";
                $response .= "Content-Type: application/json; charset=UTF-8\r\n";
                $response .= "\r\n";
                $response .= $encoded_json;
                return $response;
            }
        },
    };

    my $annotator_url = "http://localhost:$HTTP_PORT/predict.json";

    my $hs = MediaWords::Test::HashServer->new( $HTTP_PORT, $pages );

    $hs->start;

    my $config     = MediaWords::Util::Config::get_config();
    my $new_config = python_deep_copy( $config );

    # Inject NYTLabels credentials into configuration
    $new_config->{ nytlabels }                    = {};
    $new_config->{ nytlabels }->{ enabled }       = 1;
    $new_config->{ nytlabels }->{ annotator_url } = $annotator_url;
    MediaWords::Util::Config::set_config( $new_config );

    my $nytlabels = MediaWords::Util::Annotator::NYTLabels->new();

    $nytlabels->annotate_and_store_for_story( $db, $stories_id );

    my ( $annotation_exists ) = $db->query(
        <<SQL,
    	SELECT 1
    	FROM nytlabels_annotations
    	WHERE object_id = ?
SQL
        $stories_id
    )->flat;
    ok( $annotation_exists );

    $nytlabels->update_tags_for_story( $db, $stories_id );

    my $story_tags = $db->query(
        <<SQL,
    	SELECT
    		tags.tag AS tags_name,
    		tags.label AS tags_label,
    		tags.description AS tags_description,
    		tag_sets.name AS tag_sets_name,
    		tag_sets.label AS tag_sets_label,
    		tag_sets.description AS tag_sets_description
    	FROM stories_tags_map
    		INNER JOIN tags
    			ON stories_tags_map.tags_id = tags.tags_id
    		INNER JOIN tag_sets
    			ON tags.tag_sets_id = tag_sets.tag_sets_id
    	WHERE stories_tags_map.stories_id = ?
    	ORDER BY tags.tag COLLATE "C", tag_sets.name COLLATE "C"
SQL
        $stories_id
    )->hashes;

    my $expected_tags = [
        {
            'tag_sets_name'        => 'nyt_labels',
            'tags_description'     => " hurricanes \n and\r\ntropical\n\nstorms   \r\n  \n",
            'tag_sets_description' => 'NYTLabels labels',
            'tags_label'           => " hurricanes \n and\r\ntropical\n\nstorms   \r\n  \n",
            'tags_name'            => 'hurricanes and tropical storms',
            'tag_sets_label'       => 'nyt_labels'
        },
        {
            'tag_sets_label'       => 'nyt_labels_version',
            'tags_label'           => 'nyt_labeller_v1.0.0',
            'tag_sets_description' => 'NYTLabels version the story was tagged with',
            'tags_name'            => 'nyt_labeller_v1.0.0',
            'tag_sets_name'        => 'nyt_labels_version',
            'tags_description'     => 'Story was tagged with \'nyt_labeller_v1.0.0\''
        }
    ];

    cmp_deeply( $story_tags, $expected_tags );

    # Reset configuration
    MediaWords::Util::Config::set_config( $config );

    $hs->stop;
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    MediaWords::Test::DB::test_on_test_database(
        sub {
            my ( $db ) = @_;

            test_nytlabels_annotator( $db );
        }
    );
}

main();
