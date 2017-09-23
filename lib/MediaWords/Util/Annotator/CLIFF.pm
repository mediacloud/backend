package MediaWords::Util::Annotator::CLIFF;

#
# CLIFF annotator
#

use strict;
use warnings;

use Moose;
with 'MediaWords::Util::Annotator::AnnotatorRole';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use Readonly;

use MediaWords::Util::Web::UserAgent::Request;

# CLIFF version tag set
Readonly my $CLIFF_VERSION_TAG_SET => 'geocoder_version';

# CLIFF geographical names tag prefix
Readonly my $CLIFF_GEONAMES_TAG_PREFIX => 'geonames_';

sub annotator_is_enabled($)
{
    my ( $self ) = @_;

    my $config = MediaWords::Util::Config::get_config();
    my $cliff_enabled = $config->{ cliff }->{ enabled } // '';

    if ( $cliff_enabled eq 'yes' )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

sub _postgresql_raw_annotations_table($)
{
    my ( $self ) = @_;

    return 'cliff_annotations';
}

sub _request_for_text($$)
{
    my ( $self, $text ) = @_;

    my $config = MediaWords::Util::Config::get_config();

    # CLIFF annotator URL
    my $url = $config->{ cliff }->{ annotator_url };
    unless ( $url )
    {
        die "Unable to determine CLIFF annotator URL to use.";
    }

    my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $url );
    $request->set_content_type( 'application/x-www-form-urlencoded; charset=utf-8' );
    $request->set_content( { q => encode_utf8( $text ) } );

    return $request;
}

sub _fetched_annotation_is_valid($$)
{
    my ( $self, $response ) = @_;

    unless ( ref( $response ) eq ref( {} ) )
    {
        return 0;
    }

    unless ( exists( $response->{ status } ) and lc( $response->{ status } ) eq 'ok' )
    {
        return 0;
    }
    unless ( exists( $response->{ results } ) and ref( $response->{ results } ) eq ref( {} ) )
    {
        return 0;
    }

    return 1;
}

sub _tags_for_annotation($$)
{
    my ( $self, $annotation ) = @_;

    my $config = MediaWords::Util::Config::get_config();

    my $cliff_geonames_tag_set = $config->{ cliff }->{ cliff_geonames_tag_set };
    unless ( $cliff_geonames_tag_set )
    {
        die "CLIFF geographical names tag set is unset in configuration.";
    }

    my $cliff_version_tag = $config->{ cliff }->{ cliff_version_tag };
    unless ( $cliff_version_tag )
    {
        die "CLIFF version tag is unset in configuration.";
    }

    my $tags = [];

    push(
        @{ $tags },
        MediaWords::Util::Annotator::AnnotatorTag->new(
            tag_sets_name        => $CLIFF_VERSION_TAG_SET,
            tag_sets_label       => $CLIFF_VERSION_TAG_SET,
            tag_sets_description => 'CLIFF version the story was tagged with',

            tags_name        => $cliff_version_tag,
            tags_label       => $cliff_version_tag,
            tags_description => "Story was tagged with '$cliff_version_tag'",
        )
    );

    my $results = $annotation->{ results };
    unless ( $results )
    {
        return $tags;
    }

    my $places = $results->{ places };
    unless ( $places )
    {
        return $tags;
    }

    my $focus = $places->{ focus };
    unless ( $focus )
    {
        return $tags;
    }

    my $countries = $focus->{ countries };
    if ( $countries )
    {
        foreach my $country ( @{ $countries } )
        {

            push(
                @{ $tags },
                MediaWords::Util::Annotator::AnnotatorTag->new(

                    tag_sets_name        => $cliff_geonames_tag_set,
                    tag_sets_label       => $cliff_geonames_tag_set,
                    tag_sets_description => 'CLIFF geographical names',

                    # e.g. "geonames_6252001"
                    tags_name => $CLIFF_GEONAMES_TAG_PREFIX . $country->{ id },

                    # e.g. "United States"
                    tags_label => $country->{ name },

                    # e.g. "United States | A | US"
                    tags_description => sprintf(
                        '%s | %s | %s',                #
                        $country->{ name },            #
                        $country->{ featureClass },    #
                        $country->{ countryCode },     #
                    ),
                )
            );
        }
    }

    my $states = $focus->{ states };
    if ( $states )
    {
        foreach my $state ( @{ $states } )
        {
            push(
                @{ $tags },
                MediaWords::Util::Annotator::AnnotatorTag->new(
                    tag_sets_name        => $cliff_geonames_tag_set,
                    tag_sets_label       => $cliff_geonames_tag_set,
                    tag_sets_description => 'CLIFF geographical names',

                    # e.g. "geonames_4273857"
                    tags_name => $CLIFF_GEONAMES_TAG_PREFIX . $state->{ id },

                    # e.g. "Kansas"
                    tags_label => $state->{ name },

                    # e.g. "Kansas | A | KS | US"
                    tags_description => sprintf(
                        '%s | %s | %s | %s',         #
                        $state->{ name },            #
                        $state->{ featureClass },    #
                        $state->{ stateCode },       #
                        $state->{ countryCode },     #
                    ),
                )
            );
        }
    }

    return $tags;
}

no Moose;                                            # gets rid of scaffolding

1;
