package MediaWords::Util::CoreNLP;

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Process;
use MediaWords::Util::Config;
use MediaWords::Util::Web;
use MediaWords::Util::Text;
use MediaWords::Util::JSON;
use HTTP::Request;
use HTTP::Status qw(:constants);
use Encode;
use URI;
use Carp qw/confess cluck/;
use Scalar::Defer;
use Readonly;
use Data::Dumper;

# PostgreSQL table name for storing raw CoreNLP annotations
Readonly my $CORENLP_POSTGRESQL_KVS_TABLE_NAME => 'corenlp_annotations';

# Store / fetch downloads using Bzip2 compression
Readonly my $CORENLP_USE_BZIP2 => 1;

# Requested text length limit (0 for no limit)
Readonly my $CORENLP_REQUEST_TEXT_LENGTH_LIMIT => 50 * 1024;

# (Lazy-initialized) CoreNLP annotator URL
my $_corenlp_annotator_url = lazy
{

    unless ( annotator_is_enabled() )
    {
        fatal_error( "CoreNLP annotator is not enabled; why are you accessing this variable?" );
    }

    my $config = MediaWords::Util::Config->get_config();

    # CoreNLP annotator URL
    my $url = $config->{ corenlp }->{ annotator_url };
    unless ( $url )
    {
        die "Unable to determine CoreNLP annotator URL to use.";
    }

    # Validate URL
    my $uri;
    eval { $uri = URI->new( $url )->canonical; };
    if ( $@ )
    {
        fatal_error( "Invalid CoreNLP annotator URI '$url': $@" );
    }

    my $corenlp_annotator_url = $uri->as_string;
    unless ( $corenlp_annotator_url )
    {
        fatal_error( "CoreNLP annotator is enabled, but annotator URL is not set." );
    }
    say STDERR "CoreNLP annotator URL: $corenlp_annotator_url";

    return $corenlp_annotator_url;
};

# (Lazy-initialized) CoreNLP annotator timeout
my $_corenlp_annotator_timeout = lazy
{

    unless ( annotator_is_enabled() )
    {
        fatal_error( "CoreNLP annotator is not enabled; why are you accessing this variable?" );
    }

    my $config = MediaWords::Util::Config->get_config();

    # Timeout
    my $corenlp_annotator_timeout = $config->{ corenlp }->{ annotator_timeout };
    unless ( $corenlp_annotator_timeout )
    {
        die "Unable to determine CoreNLP annotator timeout to set.";
    }
    say STDERR "CoreNLP annotator timeout: $corenlp_annotator_timeout s";

    return $corenlp_annotator_timeout;
};

# (Lazy-initialized) CoreNLP annotator level (e.g. "ner" or an empty string)
my $_corenlp_annotator_level = lazy
{

    unless ( annotator_is_enabled() )
    {
        fatal_error( "CoreNLP annotator is not enabled; why are you accessing this variable?" );
    }

    my $config = MediaWords::Util::Config->get_config();

    # Level
    my $corenlp_annotator_level = $config->{ corenlp }->{ annotator_level };
    unless ( defined $corenlp_annotator_level )
    {
        die "Unable to determine CoreNLP annotator level to use.";
    }

    say STDERR "CoreNLP annotator level: $corenlp_annotator_level";

    return $corenlp_annotator_level;
};

# (Lazy-initialized) PostgreSQL key-value store
#
# We use a static, package-wide variable here because:
# a) PostgreSQL handler should support being used by multiple threads by now, and
# b) each job worker is a separate process so there shouldn't be any resource clashes.
my $_postgresql_store = lazy
{
    # this is (probably) an expensive module to load, so lazy load it
    require MediaWords::KeyValueStore::PostgreSQL;

    unless ( annotator_is_enabled() )
    {
        fatal_error( "CoreNLP annotator is not enabled; why are you accessing this variable?" );
    }

    # PostgreSQL storage
    my $postgresql_store = MediaWords::KeyValueStore::PostgreSQL->new( { table => $CORENLP_POSTGRESQL_KVS_TABLE_NAME } );
    say STDERR "Will read / write CoreNLP annotator results to PostgreSQL table: $CORENLP_POSTGRESQL_KVS_TABLE_NAME";

    return $postgresql_store;
};

# Make a request to the CoreNLP annotator, return hashref of parsed JSON
# results (without the "corenlp" key)
#
# Parameters:
# * text to be annotated
#
# Returns: hashref with parsed annotator's JSON response; "corenlp" root key is
# removed, e.g.:
#
#    {
#        "sentences": [
#            {
#                "tokens": [
#                    "..."
#                ],
#                "dependencies": [
#                    "..."
#                ],
#                "sentiments": [
#                    {
#                        "foo": "bar"
#                    }
#                ]
#            }
#        ],
#        "statistics": {
#            "foo": "bar"
#        }
#    }
#
# die()s on error
sub _annotate_text($)
{
    my $text = shift;

    unless ( $_corenlp_annotator_url )
    {
        fatal_error( "Unable to determine CoreNLP annotator URL to use." );
    }
    unless ( $_postgresql_store )
    {
        fatal_error( "PostgreSQL handler is not initialized." );
    }

    unless ( defined $text )
    {
        fatal_error( "Text is undefined." );
    }
    unless ( $text )
    {
        # CoreNLP doesn't accept empty strings, but that might happen with some
        # stories so we're just die()ing here
        die "Text is empty.";
    }

    # Trim the text because that's what the CoreNLP annotator will do, and
    # if the text is empty, we want to fail early without making a request
    # to the annotator at all
    $text =~ s/^\s+|\s+$//g;

    if ( $CORENLP_REQUEST_TEXT_LENGTH_LIMIT > 0 )
    {
        my $text_length = length( $text );
        if ( $text_length > $CORENLP_REQUEST_TEXT_LENGTH_LIMIT )
        {
            say STDERR "Text length ($text_length) has exceeded the request text " .
              "length limit ($CORENLP_REQUEST_TEXT_LENGTH_LIMIT) so I will truncate it.";
            $text = substr( $text, 0, $CORENLP_REQUEST_TEXT_LENGTH_LIMIT );
        }
    }

    unless ( MediaWords::Util::Text::is_valid_utf8( $text ) )
    {
        # Text will be encoded to JSON, so we test the UTF-8 validity before doing anything else
        die "Text is not a valid UTF-8 file: $text";
    }

    # Create JSON request
    my $text_json;
    eval {
        my $text_json_hashref = { 'text' => $text };
        if ( $_corenlp_annotator_level ne '' )
        {
            $text_json_hashref->{ 'level' } = $_corenlp_annotator_level . '';
        }
        $text_json = MediaWords::Util::JSON::encode_json( $text_json_hashref );
    };
    if ( $@ or ( !$text_json ) )
    {
        # Not critical, might happen to some stories, no need to shut down the annotator
        die "Unable to encode text to a JSON request: $@\nText: $text\nLevel: $_corenlp_annotator_level";
    }

    # Text has to be encoded because HTTP::Request only accepts bytes as POST data
    my $text_json_encoded;
    eval { $text_json_encoded = Encode::encode_utf8( $text_json ); };
    if ( $@ or ( !$text_json_encoded ) )
    {
        # Not critical, might happen to some stories, no need to shut down the annotator
        die "Unable to encode_utf8() JSON text to be annotated: $@\nJSON: $text_json";
    }

    # Make a request
    my $ua = MediaWords::Util::Web::UserAgentDetermined;
    $ua->timeout( $_corenlp_annotator_timeout );
    $ua->max_size( undef );

    my $old_after_determined_callback = $ua->after_determined_callback;
    $ua->after_determined_callback(
        sub {
            my ( $ua, $timing, $duration, $codes_to_determinate, $lwp_args, $response ) = @_;
            my $request = $lwp_args->[ 0 ];
            my $url     = $request->uri;

            unless ( $response->is_success )
            {
                if ( lc( $response->status_line ) eq '500 read timeout' )
                {
                    # die() on request timeouts without retrying anything
                    # because those usually mean that we posted something funky
                    # to the CoreNLP annotator service and it got stuck
                    die "The request timed out, giving up.";
                }
            }

            # Otherwise call the original callback subroutine
            $old_after_determined_callback->( $ua, $timing, $duration, $codes_to_determinate, $lwp_args, $response );
        }
    );

    my $request = HTTP::Request->new( POST => $_corenlp_annotator_url );
    $request->content_type( 'application/json; charset=utf8' );
    $request->content( $text_json_encoded );

    my $response = $ua->request( $request );

    # Force UTF-8 encoding on the response because the server might not always
    # return correct "Content-Type"
    my $results_string = $response->decoded_content(
        charset         => 'utf8',
        default_charset => 'utf8'
    );

    if ( $response->is_success )
    {
        # OK -- no-op
    }
    else
    {
        # Error; determine whether we should be blamed for making a malformed
        # request, or is it an extraction error

        if ( MediaWords::Util::Web::response_error_is_client_side( $response ) )
        {
            # Error was generated by LWP::UserAgent; likely didn't reach server
            # at all (timeout, unresponsive host, etc.)
            fatal_error( 'LWP error: ' . $response->status_line . ': ' . $results_string );

        }
        else
        {
            # Error was generated by server

            my $http_status_code = $response->code;

            if ( $http_status_code == HTTP_METHOD_NOT_ALLOWED or $http_status_code == HTTP_BAD_REQUEST )
            {
                # Not POST, empty POST
                fatal_error( $response->status_line . ': ' . $results_string );

            }
            elsif ( $http_status_code == HTTP_INTERNAL_SERVER_ERROR )
            {
                # CoreNLP processing error -- die() so that the error gets caught and logged into a database
                die 'CoreNLP annotator service was unable to process the download: ' . $results_string;

            }
            else
            {
                # Shutdown the extractor on unconfigured responses
                fatal_error( 'Unknown HTTP response: ' . $response->status_line . ': ' . $results_string );
            }
        }
    }

    unless ( $results_string )
    {
        die "CoreNLP annotator returned nothing for text: " . $text;
    }

    # Decode JSON response
    eval { $results_string = Encode::decode_utf8( $results_string, Encode::FB_CROAK ); };
    if ( $@ )
    {
        fatal_error( "Unable to decode string '$results_string': $@" );
    }

    # Parse resulting JSON
    my $results_hashref;
    eval { $results_hashref = MediaWords::Util::JSON::decode_json( $results_string ); };
    if ( $@ or ( !ref $results_hashref ) )
    {
        # If the JSON is invalid, it's probably something broken with the
        # remote CoreNLP service, so that's why whe do fatal_error() here
        fatal_error( "Unable to parse JSON response: $@\nJSON string: $results_string" );
    }

    # Check sanity
    unless ( exists( $results_hashref->{ corenlp } ) )
    {
        fatal_error( "Expected root key 'corenlp' doesn't exist in JSON response: $results_string" );
    }
    unless ( scalar( keys( %{ $results_hashref } ) ) == 1 )
    {
        fatal_error( "Hashref is expected to have a single 'corenlp' root key in JSON response: $results_string" );
    }

    # Remove the "corenlp" root key
    $results_hashref = $results_hashref->{ corenlp };

    # Check sanity for some more
    unless ( ref( $results_hashref ) eq ref( {} ) )
    {
        fatal_error( "Contents of 'corenlp' root key are expected to be a hashref in JSON response: $results_string" );
    }
    unless ( scalar( keys( %{ $results_hashref } ) ) > 0 )
    {
        fatal_error( "'corenlp' root key is not expected to be an empty hash in JSON response: $results_string" );
    }

    return $results_hashref;
}

# Fetch the CoreNLP annotation hashref from key-value store for the story
# Return annotation hashref on success, undef if the annotation doesn't exist
# in any of the key-value stores, die() on error
sub _fetch_raw_annotation_for_story($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( annotator_is_enabled() )
    {
        confess "CoreNLP annotator is not enabled in the configuration.";
    }

    unless ( story_is_annotated( $db, $stories_id ) )
    {
        warn "Story $stories_id is not annotated with CoreNLP.";
        return undef;
    }

    # Fetch annotation
    my $json_ref = undef;

    my $param_object_path                   = undef;                 # no such thing, objects are indexed by filename
    my $param_use_bunzip2_instead_of_gunzip = $CORENLP_USE_BZIP2;    # ...with Bzip2

    eval {
        $json_ref =
          $_postgresql_store->fetch_content( $db, $stories_id, $param_object_path, $param_use_bunzip2_instead_of_gunzip );
    };
    if ( $@ or ( !defined $json_ref ) )
    {
        die "Store died while fetching annotation for story $stories_id: $@\n";
    }

    my $json = $$json_ref;
    unless ( $json )
    {
        die "Fetched annotation is undefined or empty for story $stories_id.\n";
    }

    my $json_hashref;
    eval { $json_hashref = MediaWords::Util::JSON::decode_json( $json ); };
    if ( $@ or ( !ref $json_hashref ) )
    {
        die "Unable to parse annotation JSON for story $stories_id: $@\nString JSON: $json";
    }

    # Re-add "corenlp" root keys
    foreach my $sentence_id ( keys %{ $json_hashref } )
    {
        $json_hashref->{ $sentence_id } = { 'corenlp' => $json_hashref->{ $sentence_id } };
    }

    return $json_hashref;
}

# Returns true if CoreNLP annotator is enabled
sub annotator_is_enabled()
{
    my $config = MediaWords::Util::Config->get_config();
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

# String to use for indexing annotation JSON of the concatenation of all sentences
sub sentences_concatenation_index()
{
    return '_';
}

# Check if story can be annotated with CoreNLP
# Return 1 if story can be annotated, 0 otherwise, die() on error, exit() on fatal error
sub story_is_annotatable($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( annotator_is_enabled() )
    {
        fatal_error( "CoreNLP annotator is not enabled in the configuration." );
    }

    my $story = $db->query(
        <<EOF,
        SELECT story_is_annotatable_with_corenlp
        FROM story_is_annotatable_with_corenlp(?)
EOF
        $stories_id
    )->hash;
    if ( $story->{ story_is_annotatable_with_corenlp } )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Check if story is annotated with CoreNLP
# Return 1 if story is annotated, 0 otherwise, die() on error, exit() on fatal error
sub story_is_annotated($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( annotator_is_enabled() )
    {
        fatal_error( "CoreNLP annotator is not enabled in the configuration." );
    }

    my $annotation_exists = undef;
    eval { $annotation_exists = $_postgresql_store->content_exists( $db, $stories_id ); };
    if ( $@ )
    {
        die "Storage died while testing whether or not an annotation exists for story $stories_id: $@";
    }

    if ( $annotation_exists )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Run the CoreNLP annotation for the story, store results in key-value store
# If story is already annotated, issue a warning and overwrite
# Return 1 on success, 0 on failure, die() on error, exit() on fatal error
sub store_annotation_for_story($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( annotator_is_enabled() )
    {
        fatal_error( "CoreNLP annotator is not enabled in the configuration." );
        return 0;
    }

    if ( story_is_annotated( $db, $stories_id ) )
    {
        warn "Story $stories_id is already annotated with CoreNLP, so I will overwrite it.";
    }

    unless ( story_is_annotatable( $db, $stories_id ) )
    {
        warn "Story $stories_id is not annotatable.";
        return 0;
    }

    my $story_sentences = $db->query(
        <<EOF,
        SELECT story_sentences_id, sentence_number, sentence
        FROM story_sentences
        WHERE stories_id = ?
        ORDER BY sentence_number
EOF
        $stories_id
    )->hashes;
    unless ( ref $story_sentences )
    {
        die "Unable to fetch story sentences for story $stories_id.";
    }

    my %annotations;

    say STDERR "Annotating sentences and story text for story $stories_id...";

    # Annotate each sentence separately, index by story_sentences_id
    foreach my $sentence ( @{ $story_sentences } )
    {
        my $sentence_id     = $sentence->{ story_sentences_id } + 0;
        my $sentence_number = $sentence->{ sentence_number } + 0;
        my $sentence_text   = $sentence->{ sentence };

        say STDERR "Annotating story's $stories_id sentence " . ( $sentence_number + 1 ) . " / " .
          scalar( @{ $story_sentences } ) . "...";
        $annotations{ $sentence_id } = _annotate_text( $sentence_text );
        unless ( defined $annotations{ $sentence_id } )
        {
            die "Unable to annotate story sentence $sentence_id.";
        }
    }

    # Annotate concatenation of all sentences, index as '_'
    my $sentences_concat_text = join( ' ', map { $_->{ sentence } } @{ $story_sentences } );

    say STDERR "Annotating story's $stories_id concatenated sentences...";
    my $concat_index = sentences_concatenation_index() . '';
    $annotations{ $concat_index } = _annotate_text( $sentences_concat_text );
    unless ( $annotations{ $concat_index } )
    {
        die "Unable to annotate story sentences concatenation for story $stories_id.\n";
    }

    # Convert results to a minimized JSON
    my $json_annotation;
    eval { $json_annotation = MediaWords::Util::JSON::encode_json( \%annotations ); };
    if ( $@ or ( !$json_annotation ) )
    {
        fatal_error( "Unable to encode hashref to JSON: $@\nHashref: " . Dumper( $json_annotation ) );
        return 0;
    }

    say STDERR "Done annotating sentences and story text for story $stories_id.";
    say STDERR 'JSON length: ' . length( $json_annotation );

    say STDERR "Storing annotation results for story $stories_id...";

    # Write to PostgreSQL, index by stories_id
    eval {
        # objects should be compressed with Bzip2
        my $param_use_bzip2_instead_of_gzip = $CORENLP_USE_BZIP2;

        my $path =
          $_postgresql_store->store_content( $db, $stories_id, \$json_annotation, $param_use_bzip2_instead_of_gzip );
    };
    if ( $@ )
    {
        fatal_error( "Unable to store CoreNLP annotation result: $@" );
        return 0;
    }
    say STDERR "Done storing annotation results for story $stories_id.";

    return 1;
}

# Fetch the CoreNLP annotation JSON from key-value store for the story
# Return string JSON on success, undef if the annotation doesn't exist in any
# key-value stores, die() on error
sub fetch_annotation_json_for_story($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( annotator_is_enabled() )
    {
        confess "CoreNLP annotator is not enabled in the configuration.";
    }

    unless ( story_is_annotated( $db, $stories_id ) )
    {
        warn "Story $stories_id is not annotated with CoreNLP.";
        return undef;
    }

    my $annotation;
    eval { $annotation = _fetch_raw_annotation_for_story( $db, $stories_id ); };
    if ( $@ or ( !defined $annotation ) )
    {
        die "Unable to fetch annotation for story $stories_id: $@";
    }

    my $sentences_concat_text = sentences_concatenation_index() . '';
    unless ( exists( $annotation->{ $sentences_concat_text } ) )
    {
        die "Annotation of the concatenation of all sentences under concatenation index " .
          "'$sentences_concat_text' doesn't exist for story $stories_id";
    }

    # Test sanity
    my $story_annotation = $annotation->{ $sentences_concat_text };
    unless ( exists $story_annotation->{ corenlp } )
    {
        die "Story annotation does not have 'corenlp' root key for story $stories_id";
    }

    # Encode back to JSON, prettifying the result
    my $story_annotation_json;
    eval { $story_annotation_json = MediaWords::Util::JSON::encode_json( $story_annotation, 1 ); };
    if ( $@ or ( !$story_annotation_json ) )
    {
        die "Unable to encode story annotation to JSON for story $stories_id: $@\nHashref: " . Dumper( $story_annotation );
    }

    return $story_annotation_json;
}

# Fetch the CoreNLP annotation JSON from key-value store for the story sentence
# Return string JSON on success, undef if the annotation doesn't exist in any
# key-value stores, die() on error
sub fetch_annotation_json_for_story_sentence($$)
{
    my ( $db, $story_sentences_id ) = @_;

    unless ( annotator_is_enabled() )
    {
        confess "CoreNLP annotator is not enabled in the configuration.";
    }

    my $story_sentence = $db->find_by_id( 'story_sentences', $story_sentences_id );
    unless ( $story_sentence->{ story_sentences_id } )
    {
        die "Story sentence with ID $story_sentences_id was not found.";
    }

    my $stories_id = $story_sentence->{ stories_id } + 0;

    unless ( story_is_annotated( $db, $stories_id ) )
    {
        warn "Story $stories_id is not annotated with CoreNLP.";
        return undef;
    }

    my $annotation;
    eval { $annotation = _fetch_raw_annotation_for_story( $db, $stories_id ); };
    if ( $@ or ( !defined $annotation ) )
    {
        die "Unable to fetch annotation for story $stories_id: $@";
    }

    unless ( exists( $annotation->{ $story_sentences_id } ) )
    {
        die "Annotation for story sentence $story_sentences_id does not exist in story's $stories_id annotation.";
    }

    # Test sanity
    my $story_sentence_annotation = $annotation->{ $story_sentences_id };
    unless ( exists $story_sentence_annotation->{ corenlp } )
    {
        die "Sentence annotation does not have 'corenlp' root key for story sentence " .
          $story_sentences_id . ", story $stories_id";
    }

    # Encode back to JSON, prettifying the result
    my $story_sentence_annotation_json;
    eval { $story_sentence_annotation_json = MediaWords::Util::JSON::encode_json( $story_sentence_annotation, 1 ); };
    if ( $@ or ( !$story_sentence_annotation_json ) )
    {
        die "Unable to encode sentence annotation to JSON for story sentence " .
          $story_sentences_id . ", story $stories_id: $@\nHashref: " . Dumper( $story_sentence_annotation );
    }

    return $story_sentence_annotation_json;
}

# Fetch the CoreNLP annotation JSON from key-value store for the story and all
# its sentences
#
# Annotation for the concatenation of all sentences will have a key of
# sentences_concatenation_index(), e.g.:
#
# {
#     '_' => { 'corenlp' => 'annotation of the concatenation of all story sentences' },
#     1 => { 'corenlp' => 'annotation of the sentence with story_sentences_id => 1' },
#     2 => { 'corenlp' => 'annotation of the sentence with story_sentences_id => 2' },
#     3 => { 'corenlp' => 'annotation of the sentence with story_sentences_id => 3' },
#     ...
# }
#
# Return string JSON on success, undef if the annotation doesn't exist in any
# key-value stores, die() on error
sub fetch_annotation_json_for_story_and_all_sentences($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( annotator_is_enabled() )
    {
        confess "CoreNLP annotator is not enabled in the configuration.";
    }

    unless ( story_is_annotated( $db, $stories_id ) )
    {
        warn "Story $stories_id is not annotated with CoreNLP.";
        return undef;
    }

    my $annotation;
    eval { $annotation = _fetch_raw_annotation_for_story( $db, $stories_id ); };
    if ( $@ or ( !defined $annotation ) )
    {
        die "Unable to fetch annotation for story $stories_id: $@";
    }

    # Test sanity
    my $sentences_concat_text = sentences_concatenation_index() . '';
    unless ( exists( $annotation->{ $sentences_concat_text } ) )
    {
        die "Annotation of the concatenation of all sentences under concatenation index " .
          "'$sentences_concat_text' doesn't exist for story $stories_id";
    }

    # Encode back to JSON, prettifying the result
    my $annotation_json;
    eval { $annotation_json = MediaWords::Util::JSON::encode_json( $annotation, 1 ); };
    if ( $@ or ( !$annotation_json ) )
    {
        die "Unable to encode story and its sentences annotation to JSON for story " .
          $stories_id . ": $@\nHashref: " . Dumper( $annotation );
    }

    return $annotation_json;
}

1;
