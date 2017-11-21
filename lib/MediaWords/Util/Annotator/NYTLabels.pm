package MediaWords::Util::Annotator::NYTLabels;

#
# NYTLabels annotator
#

use strict;
use warnings;

use Moose;
with 'MediaWords::Util::Annotator::AnnotatorRole';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Encode;
use Readonly;

use MediaWords::Util::JSON;
use MediaWords::Util::Web::UserAgent::Request;

# NYTLabels version tag set
Readonly my $NYTLABELS_VERSION_TAG_SET => 'nyt_labels_version';

# Story will be tagged with labels for which the score is above this threshold
Readonly my $NYTLABELS_SCORE_THRESHOLD => 0.2;

sub annotator_is_enabled($)
{
    my ( $self ) = @_;

    my $config = MediaWords::Util::Config::get_config();
    my $nytlabels_enabled = $config->{ nytlabels }->{ enabled } // '';

    if ( $nytlabels_enabled eq 'yes' )
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

    return 'nytlabels_annotations';
}

sub _request_for_text($$)
{
    my ( $self, $text ) = @_;

    my $config = MediaWords::Util::Config::get_config();

    # NYTLabels annotator URL
    my $url = $config->{ nytlabels }->{ annotator_url };
    unless ( $url )
    {
        die "Unable to determine NYTLabels annotator URL to use.";
    }

    # Create JSON request
    DEBUG "Converting text to JSON request...";
    my $text_json;
    eval {
        my $text_json_hashref = { 'text' => $text };
        $text_json = MediaWords::Util::JSON::encode_json( $text_json_hashref );
    };
    if ( $@ or ( !$text_json ) )
    {
        # Not critical, might happen to some stories, no need to shut down the annotator
        die "Unable to encode text to a JSON request: $@\nText: $text";
    }
    DEBUG "Done converting text to JSON request.";

    my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $url );
    $request->set_content_type( 'application/json; charset=utf-8' );
    $request->set_content( $text_json );

    return $request;
}

sub _fetched_annotation_is_valid($$)
{
    my ( $self, $response ) = @_;

    unless ( exists( $response->{ descriptors600 } ) )
    {
        return 0;
    }

    return 1;
}

sub _tags_for_annotation($$)
{
    my ( $self, $annotation ) = @_;

    my $config = MediaWords::Util::Config::get_config();

    my $nytlabels_labels_tag_set = $config->{ nytlabels }->{ nytlabels_labels_tag_set };
    unless ( $nytlabels_labels_tag_set )
    {
        die "NYTLabels labels tag set is unset in configuration.";
    }

    my $nytlabels_version_tag = $config->{ nytlabels }->{ nytlabels_version_tag };
    unless ( $nytlabels_version_tag )
    {
        die "NYTLabels version tag is unset in configuration.";
    }

    my $tags = [];

    push(
        @{ $tags },
        MediaWords::Util::Annotator::AnnotatorTag->new(
            tag_sets_name        => $NYTLABELS_VERSION_TAG_SET,
            tag_sets_label       => $NYTLABELS_VERSION_TAG_SET,
            tag_sets_description => 'NYTLabels version the story was tagged with',

            tags_name        => $nytlabels_version_tag,
            tags_label       => $nytlabels_version_tag,
            tags_description => "Story was tagged with '$nytlabels_version_tag'",
        )
    );

    my $descriptors600 = $annotation->{ descriptors600 };
    unless ( $descriptors600 )
    {
        return $tags;
    }

    foreach my $descriptor ( @{ $descriptors600 } )
    {
        my $label = $descriptor->{ label };
        my $score = $descriptor->{ score } + 0.0;

        if ( $score > $NYTLABELS_SCORE_THRESHOLD + 0.0 )
        {
            push(
                @{ $tags },
                MediaWords::Util::Annotator::AnnotatorTag->new(
                    tag_sets_name        => $nytlabels_labels_tag_set,
                    tag_sets_label       => $nytlabels_labels_tag_set,
                    tag_sets_description => 'NYTLabels labels',

                    # e.g. "hurricanes and tropical storms"
                    tags_name        => $label,
                    tags_label       => $label,
                    tags_description => $label,
                )
            );
        }
        else
        {
            TRACE "Skipping label '$label' because its score $score is lower than the threshold $NYTLABELS_SCORE_THRESHOLD";
        }
    }

    return $tags;
}

no Moose;    # gets rid of scaffolding

1;
