package MediaWords::Util::Annotator::CoreNLP;

#
# CoreNLP annotator
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

sub annotator_is_enabled($)
{
    my ( $self ) = @_;

    my $config = MediaWords::Util::Config::get_config();
    my $corenlp_enabled = $config->{ corenlp }->{ enabled } // '';

    if ( $corenlp_enabled eq 'yes' )
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

    return 'corenlp_annotations';
}

sub _request_for_text($$)
{
    my ( $self, $text ) = @_;

    my $config = MediaWords::Util::Config::get_config();

    # CoreNLP annotator URL
    my $url = $config->{ corenlp }->{ annotator_url };
    unless ( $url )
    {
        die "Unable to determine CoreNLP annotator URL to use.";
    }

    my $corenlp_annotator_level = $config->{ corenlp }->{ annotator_level };
    unless ( defined $corenlp_annotator_level )
    {
        die "Unable to determine CoreNLP annotator level to use.";
    }

    # Create JSON request
    DEBUG "Converting text to JSON request...";
    my $text_json;
    eval {
        my $text_json_hashref = { 'text' => $text };
        if ( $corenlp_annotator_level ne '' )
        {
            $text_json_hashref->{ 'level' } = $corenlp_annotator_level . '';
        }
        $text_json = MediaWords::Util::JSON::encode_json( $text_json_hashref );
    };
    if ( $@ or ( !$text_json ) )
    {
        # Not critical, might happen to some stories, no need to shut down the annotator
        die "Unable to encode text to a JSON request: $@\nText: $text\nLevel: $corenlp_annotator_level";
    }
    DEBUG "Done converting text to JSON request.";

    # Text has to be encoded because MediaWords::Util::Web::UserAgent::Request
    # only accepts bytes as POST data
    DEBUG "Encoding JSON request...";
    my $text_json_encoded;
    eval { $text_json_encoded = encode_utf8( $text_json ); };
    if ( $@ or ( !$text_json_encoded ) )
    {
        # Not critical, might happen to some stories, no need to shut down the annotator
        die "Unable to encode_utf8() JSON text to be annotated: $@\nJSON: $text_json";
    }
    DEBUG "Done encoding JSON request.";

    my $request = MediaWords::Util::Web::UserAgent::Request->new( 'POST', $url );
    $request->set_content_type( 'application/json; charset=utf-8' );
    $request->set_content( $text_json_encoded );

    return $request;
}

sub _fetched_annotation_is_valid($$)
{
    my ( $self, $response ) = @_;

    unless ( exists( $response->{ corenlp } ) )
    {
        return 0;
    }
    unless ( scalar( keys( %{ $response } ) ) == 1 )
    {
        return 0;
    }

    return 1;
}

sub _tags_for_annotation($$)
{
    my ( $self, $annotation ) = @_;

    fatal_error( "No tags derived from CoreNLP annotations at the moment." );
}

# (static) String to use for indexing annotation JSON of the concatenation of all sentences
sub sentences_concatenation_index()
{
    return '_';
}

sub _postprocess_fetched_annotation($$)
{
    my ( $self, $response ) = @_;

    # Remove the "corenlp" root key
    $response = $response->{ corenlp };

    # Check sanity for some more
    unless ( ref( $response ) eq ref( {} ) )
    {
        fatal_error(
            "Contents of 'corenlp' root key are expected to be a hashref in JSON response: " . Dumper( $response ) );
    }
    unless ( scalar( keys( %{ $response } ) ) > 0 )
    {
        fatal_error( "'corenlp' root key is not expected to be an empty hash in JSON response: " . Dumper( $response ) );
    }

    $response = { sentences_concatenation_index() => $response, };

    return $response;
}

sub _preprocess_stored_annotation($$)
{
    my ( $self, $response ) = @_;

    # Re-add "corenlp" root keys
    foreach my $sentence_id ( keys %{ $response } )
    {
        $response->{ $sentence_id } = { 'corenlp' => $response->{ $sentence_id } };
    }

    return $response;
}

no Moose;    # gets rid of scaffolding

1;
