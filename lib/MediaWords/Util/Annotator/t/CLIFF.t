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

use MediaWords::Util::Annotator::CLIFF;
use MediaWords::Util::ParseJSON;

use MediaWords::Test::HTTP::HashServer;
use MediaWords::Test::DB;

Readonly my $HTTP_PORT => 8912;

sub _sample_cliff_response()
{
    return {
        "milliseconds" => 231,
        "results"      => {
            "organizations" => [
                {
                    "count" => 2,

                    # Newlines should be replaced to spaces, string should get trimmed
                    "name" => " Kansas\nHealth\nInstitute   \n  ",
                },
                {
                    "count" => 2,

                    # Test whether tags that already exist get merged into one
                    "name" => "Kansas Health Institute",
                },
                {
                    "count" => 3,
                    "name"  => "Census Bureau",
                },
            ],
            "people" => [
                {
                    "count" => 7,
                    "name"  => "Tim Huelskamp",
                },
                {
                    "count" => 5,
                    "name"  => "a.k.a. Obamacare",
                },
            ],
            "places" => {
                "focus" => {
                    "cities" => [
                        {
                            "countryCode"      => "US",
                            "countryGeoNameId" => "6252001",
                            "featureClass"     => "P",
                            "featureCode"      => "PPLA2",
                            "id"               => 5391959,
                            "lat"              => 37.77493,
                            "lon"              => -122.41942,
                            "name"             => "San Francisco",
                            "population"       => 805235,
                            "score"            => 1,
                            "stateCode"        => "CA",
                            "stateGeoNameId"   => "5332921",
                        },
                        {
                            "countryCode"      => "US",
                            "countryGeoNameId" => "6252001",
                            "featureClass"     => "P",
                            "featureCode"      => "PPL",
                            "id"               => 5327684,
                            "lat"              => 37.87159,
                            "lon"              => -122.27275,
                            "name"             => "Berkeley",
                            "population"       => 112580,
                            "score"            => 1,
                            "stateCode"        => "CA",
                            "stateGeoNameId"   => "5332921",
                        }
                    ],
                    "countries" => [
                        {
                            "countryCode"      => "US",
                            "countryGeoNameId" => "6252001",
                            "featureClass"     => "A",
                            "featureCode"      => "PCLI",
                            "id"               => 6252001,
                            "lat"              => 39.76,
                            "lon"              => -98.5,
                            "name"             => "United States",
                            "population"       => 310232863,
                            "score"            => 10,
                            "stateCode"        => "00",
                            "stateGeoNameId"   => "",
                        }
                    ],
                    "states" => [
                        {
                            "countryCode"      => "US",
                            "countryGeoNameId" => "6252001",
                            "featureClass"     => "A",
                            "featureCode"      => "ADM1",
                            "id"               => 4273857,
                            "lat"              => 38.50029,
                            "lon"              => -98.50063,
                            "name"             => "Kansas",
                            "population"       => 2740759,
                            "score"            => 10,
                            "stateCode"        => "KS",
                            "stateGeoNameId"   => "4273857",
                        },
                        {
                            "countryCode"      => "US",
                            "countryGeoNameId" => "6252001",
                            "featureClass"     => "A",
                            "featureCode"      => "ADM1",
                            "id"               => 5332921,
                            "lat"              => 37.25022,
                            "lon"              => -119.75126,
                            "name"             => "California",
                            "population"       => 37691912,
                            "score"            => 2,
                            "stateCode"        => "CA",
                            "stateGeoNameId"   => "5332921",
                        },
                    ],
                },
            },
            "mentions" => [
                {
                    "confidence"       => 1,
                    "countryCode"      => "US",
                    "countryGeoNameId" => "6252001",
                    "featureClass"     => "A",
                    "featureCode"      => "ADM1",
                    "id"               => 4273857,
                    "lat"              => 38.50029,
                    "lon"              => -98.50063,
                    "name"             => "Kansas",
                    "population"       => 2740759,
                    "source"           => {
                        "charIndex" => 162,
                        "string"    => "Kansas",
                    },
                    "stateCode"      => "KS",
                    "stateGeoNameId" => "4273857",
                },
                {
                    "confidence"       => 1,
                    "countryCode"      => "US",
                    "countryGeoNameId" => "6252001",
                    "featureClass"     => "P",
                    "featureCode"      => "PPL",
                    "id"               => 5327684,
                    "lat"              => 37.87159,
                    "lon"              => -122.27275,
                    "name"             => "Berkeley",
                    "population"       => 112580,
                    "source"           => {
                        "charIndex" => 6455,
                        "string"    => "Berkeley",
                    },
                    "stateCode"      => "CA",
                    "stateGeoNameId" => "5332921",
                },
            ],
        },
        "status"  => "ok",
        "version" => "2.4.1",
    };
}

sub test_cliff_annotator($)
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
            sentence        => 'I hope that the CLIFF annotator is working.',
            media_id        => $media->{ media_id },
            publish_date    => MediaWords::Util::SQL::get_sql_date_from_epoch( time() ),
            language        => 'en'
        }
    );

    my $encoded_json = MediaWords::Util::ParseJSON::encode_json( _sample_cliff_response() );

    my $pages = {

        # Mock annotator
        '/cliff/parse/text' => {
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

    my $annotator_url = "http://localhost:$HTTP_PORT/cliff/parse/text";

    my $hs = MediaWords::Test::HTTP::HashServer->new( $HTTP_PORT, $pages );

    $hs->start;

    my $config     = MediaWords::Util::Config::get_config();
    my $new_config = python_deep_copy( $config );

    # Inject CLIFF credentials into configuration
    $new_config->{ cliff }                    = {};
    $new_config->{ cliff }->{ enabled }       = 1;
    $new_config->{ cliff }->{ annotator_url } = $annotator_url;
    MediaWords::Util::Config::set_config( $new_config );

    my $cliff = MediaWords::Util::Annotator::CLIFF->new();

    $cliff->annotate_and_store_for_story( $db, $stories_id );

    my ( $annotation_exists ) = $db->query(
        <<SQL,
    	SELECT 1
    	FROM cliff_annotations
    	WHERE object_id = ?
SQL
        $stories_id
    )->flat;
    ok( $annotation_exists );

    $cliff->update_tags_for_story( $db, $stories_id );

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
            'tag_sets_name'        => 'cliff_organizations',
            'tags_label'           => 'Census Bureau',
            'tags_name'            => 'Census Bureau',
            'tags_description'     => 'Census Bureau',
            'tag_sets_description' => 'CLIFF organizations',
            'tag_sets_label'       => 'cliff_organizations'
        },
        {
            'tags_name'            => 'Kansas Health Institute',
            'tag_sets_name'        => 'cliff_organizations',
            'tags_label'           => " Kansas\nHealth\nInstitute   \n  ",
            'tag_sets_label'       => 'cliff_organizations',
            'tag_sets_description' => 'CLIFF organizations',
            'tags_description'     => " Kansas\nHealth\nInstitute   \n  "
        },
        {
            'tags_description'     => 'Tim Huelskamp',
            'tag_sets_label'       => 'cliff_people',
            'tag_sets_description' => 'CLIFF people',
            'tag_sets_name'        => 'cliff_people',
            'tags_label'           => 'Tim Huelskamp',
            'tags_name'            => 'Tim Huelskamp'
        },
        {
            'tags_name'            => 'a.k.a. Obamacare',
            'tag_sets_name'        => 'cliff_people',
            'tags_label'           => 'a.k.a. Obamacare',
            'tag_sets_description' => 'CLIFF people',
            'tag_sets_label'       => 'cliff_people',
            'tags_description'     => 'a.k.a. Obamacare'
        },
        {
            'tags_description'     => 'Story was tagged with \'cliff_clavin_v2.4.1\'',
            'tag_sets_label'       => 'geocoder_version',
            'tag_sets_description' => 'CLIFF version the story was tagged with',
            'tags_label'           => 'cliff_clavin_v2.4.1',
            'tag_sets_name'        => 'geocoder_version',
            'tags_name'            => 'cliff_clavin_v2.4.1'
        },
        {
            'tags_label'           => 'Kansas',
            'tag_sets_name'        => 'cliff_geonames',
            'tags_name'            => 'geonames_4273857',
            'tags_description'     => 'Kansas | A | KS | US',
            'tag_sets_description' => 'CLIFF geographical names',
            'tag_sets_label'       => 'cliff_geonames'
        },
        {
            'tags_label'           => 'Berkeley',
            'tag_sets_name'        => 'cliff_geonames',
            'tags_name'            => 'geonames_5327684',
            'tags_description'     => 'Berkeley | P | CA | US',
            'tag_sets_description' => 'CLIFF geographical names',
            'tag_sets_label'       => 'cliff_geonames'
        },
        {
            'tags_name'            => 'geonames_5332921',
            'tag_sets_name'        => 'cliff_geonames',
            'tags_label'           => 'California',
            'tag_sets_label'       => 'cliff_geonames',
            'tag_sets_description' => 'CLIFF geographical names',
            'tags_description'     => 'California | A | CA | US'
        },
        {
            'tag_sets_name'        => 'cliff_geonames',
            'tags_label'           => 'San Francisco',
            'tags_name'            => 'geonames_5391959',
            'tags_description'     => 'San Francisco | P | CA | US',
            'tag_sets_description' => 'CLIFF geographical names',
            'tag_sets_label'       => 'cliff_geonames'
        },
        {
            'tag_sets_description' => 'CLIFF geographical names',
            'tag_sets_label'       => 'cliff_geonames',
            'tags_description'     => 'United States | A | US',
            'tags_name'            => 'geonames_6252001',
            'tags_label'           => 'United States',
            'tag_sets_name'        => 'cliff_geonames'
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

            test_cliff_annotator( $db );
        }
    );
}

main();
