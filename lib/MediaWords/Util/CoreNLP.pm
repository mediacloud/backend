package MediaWords::Util::CoreNLP;

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::Util::Web;
use MediaWords::KeyValueStore::GridFS;
use MediaWords::Util::Text;
use HTTP::Request;
use HTTP::Status qw(:constants);
use Encode;
use URI;
use JSON;
use Data::Dumper;

# Store / fetch downloads using Bzip2 compression
use constant CORENLP_GRIDFS_USE_BZIP2 => 1;

# (Cached) CoreNLP annotator URL
my $_corenlp_annotator_url;        # lazy-initialized in BEGIN()
my $_corenlp_annotator_timeout;    # lazy-initialized in BEGIN()

# MongoDB GridFS key-value store
# We use a static one here because:
# a) MongoDB handler should support being used by multiple threads by now, and
# b) each Gearman worker is a separate process so there shouldn't be any resource clashes.
my $_gridfs_store;    # lazy-initialized in BEGIN()

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

BEGIN
{
    if ( annotator_is_enabled() )
    {

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
            _fatal_error( "Invalid CoreNLP annotator URI '$url': $@" );
        }

        $_corenlp_annotator_url = $uri->as_string;
        unless ( $_corenlp_annotator_url )
        {
            _fatal_error( "CoreNLP annotator is enabled, but annotator URL is not set." );
        }
        say STDERR "CoreNLP annotator URL: $_corenlp_annotator_url";

        # Timeout
        $_corenlp_annotator_timeout = $config->{ corenlp }->{ annotator_timeout };
        unless ( $_corenlp_annotator_timeout )
        {
            die "Unable to determine CoreNLP annotator timeout to set.";
        }
        say STDERR "CoreNLP annotator timeout: $_corenlp_annotator_timeout s";

        # GridFS storage
        my $gridfs_database_name = $config->{ mongodb_gridfs }->{ corenlp }->{ database_name };
        unless ( $gridfs_database_name )
        {
            _fatal_error( "CoreNLP annotator is enabled, but MongoDB GridFS database name is not set." );
        }
        $_gridfs_store = MediaWords::KeyValueStore::GridFS->new( { database_name => $gridfs_database_name } );
        say STDERR "Will write CoreNLP annotator results to GridFS database: $gridfs_database_name";
    }
}

# Encode hashref to JSON, die() on error
sub _encode_json($;$)
{
    my ( $hashref, $pretty ) = @_;

    $pretty = ( $pretty ? 1 : 0 );

    unless ( ref( $hashref ) eq ref( {} ) )
    {
        die "Parameter is not a hashref: " . Dumper( $hashref );
    }

    my $json;
    eval { $json = JSON->new->utf8( 1 )->pretty( $pretty )->encode( $hashref ); };
    if ( $@ or ( !$json ) )
    {
        die "Unable to encode hashref to JSON: $@\nHashref: " . Dumper( $hashref );
    }

    return $json;
}

# Decode JSON to hashref, die() on error
sub _decode_json($)
{
    my $json = shift;

    unless ( $json )
    {
        die "JSON is empty or undefined.\n";
    }

    my $hashref;
    eval { $hashref = decode_json $json; };
    if ( $@ or ( !$hashref ) )
    {
        die "Unable to decode JSON to hashref: $@\nJSON: $json";
    }

    return $hashref;
}

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
        _fatal_error( "Unable to determine CoreNLP annotator URL to use." );
    }
    unless ( $_gridfs_store )
    {
        _fatal_error( "GridFS handler is not initialized." );
    }

    if ( defined $text )
    {
        # Trim the text because that's what the CoreNLP annotator will do, and
        # if the text is empty, we want to fail early without making a request
        # to the annotator at all
        $text =~ s/^\s+|\s+$//g;
    }
    unless ( $text )
    {
        # CoreNLP doesn't accept empty strings, but that might happen with some stories
        die "Text is undefined or empty.";
    }
    unless ( MediaWords::Util::Text::is_valid_utf8( $text ) )
    {
        # Text will be encoded to JSON, so we test the UTF-8 validity before doing anything else
        die "Text is not a valid UTF-8 file: $text";
    }

    # Create JSON request
    my $text_json;
    eval { $text_json = _encode_json( { 'text' => $text } ); };
    if ( $@ or ( !$text_json ) )
    {
        # Not critical, might happen to some stories, no need to shut down the annotator
        die "Unable to encode text to a JSON request: $@\nText: $text";
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
    my $ua = MediaWords::Util::Web::UserAgent;
    $ua->timeout( $_corenlp_annotator_timeout );
    $ua->max_size( undef );

    my $request = HTTP::Request->new( POST => $_corenlp_annotator_url );
    $request->content_type( 'application/json; charset=utf8' );
    $request->content( $text_json_encoded );

    my $response       = $ua->request( $request );
    my $results_string = $response->decoded_content;

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
            _fatal_error( 'LWP error: ' . $response->status_line . ': ' . $results_string );

        }
        else
        {
            # Error was generated by server

            my $http_status_code = $response->code;

            if ( $http_status_code == HTTP_METHOD_NOT_ALLOWED or $http_status_code == HTTP_BAD_REQUEST )
            {
                # Not POST, empty POST
                _fatal_error( $response->status_line . ': ' . $results_string );

            }
            elsif ( $http_status_code == HTTP_INTERNAL_SERVER_ERROR )
            {
                # CRF processing error -- die() so that the error gets caught and logged into a database
                die 'CoreNLP annotator service was unable to process the download: ' . $results_string;

            }
            else
            {
                # Shutdown the extractor on unconfigured responses
                _fatal_error( 'Unknown HTTP response: ' . $response->status_line . ': ' . $results_string );
            }
        }
    }

    unless ( $results_string )
    {
        die "CoreNLP annotator returned nothing for text: " . $text;
    }

    # Parse resulting JSON
    my $results_hashref;
    eval { $results_hashref = _decode_json( $results_string ); };
    if ( $@ or ( !ref $results_hashref ) )
    {
        # If the JSON is invalid, it's probably something broken with the
        # remote CoreNLP service, so that's why whe do _fatal_error() here
        _fatal_error( "Unable to parse JSON response: $@\nJSON string: $results_string" );
    }

    # Check sanity
    unless ( exists( $results_hashref->{ corenlp } ) )
    {
        _fatal_error( "Expected root key 'corenlp' doesn't exist in JSON response: $results_string" );
    }
    unless ( scalar( keys( %{ $results_hashref } ) ) == 1 )
    {
        _fatal_error( "Hashref is expected to have a single 'corenlp' root key in JSON response: $results_string" );
    }

    # Remove the "corenlp" root key
    $results_hashref = $results_hashref->{ corenlp };

    # Check sanity for some more
    unless ( ref( $results_hashref ) eq ref( {} ) )
    {
        _fatal_error( "Contents of 'corenlp' root key are expected to be a hashref in JSON response: $results_string" );
    }
    unless ( scalar( keys( %{ $results_hashref } ) ) > 0 )
    {
        _fatal_error( "'corenlp' root key is not expected to be an empty hash in JSON response: $results_string" );
    }

    return $results_hashref;
}

# Fetch the CoreNLP annotation hashref from MongoDB for the story
# Return annotation hashref on success, undef if the annotation doesn't exist in MongoDB, die() on error
sub _fetch_annotation_from_gridfs_for_story($$)
{
    my ( $db, $stories_id ) = @_;

    if ( !annotator_is_enabled() )
    {
        die "CoreNLP annotator is not enabled in the configuration.";
    }

    unless ( story_is_annotated( $db, $stories_id ) )
    {
        warn "Story $stories_id is not annotated with CoreNLP.";
        return undef;
    }

    # Fetch annotation
    my $json_ref = undef;

    my $param_object_path                   = undef;                         # no such thing, objects are indexed by filename
    my $param_skip_uncompress_and_decode    = 0;                             # objects are compressed...
    my $param_use_bunzip2_instead_of_gunzip = CORENLP_GRIDFS_USE_BZIP2 + 0;  # ...with Bzip2

    eval {
        $json_ref = $_gridfs_store->fetch_content(
            $db, $stories_id, $param_object_path,
            $param_skip_uncompress_and_decode,
            $param_use_bunzip2_instead_of_gunzip
        );
    };
    if ( $@ or ( !defined $json_ref ) )
    {
        die "GridFS died while fetching annotation for story $stories_id: $@\n";
    }

    my $json = $$json_ref;
    unless ( $json )
    {
        die "Fetched annotation is undefined or empty for story $stories_id.\n";
    }

    my $json_hashref;
    eval { $json_hashref = _decode_json( $json ); };
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

sub _fatal_error($)
{
    # There are errors that cannot be classified as CoreNLP annotator errors
    # (that would get logged into the database). For example, if the whole
    # CoreNLP annotator service is down, no text processing of any kind can
    # happen anyway, so it's not worthwhile to log those errors into the
    # database.
    #
    # Instead, we go the radical way of killing the whole CoreNLP annotator
    # client process. It is more likely that someone will notice that the
    # CoreNLP annotator client script service is malfunctioning if the script
    # gets shut down.
    #
    # Usual die() wouldn't work here because it is (might be) wrapped into an
    # eval{}.

    my $error_message = shift;

    say STDERR $error_message;
    exit 1;
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

    if ( !annotator_is_enabled() )
    {
        _fatal_error( "CoreNLP annotator is not enabled in the configuration." );
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

    if ( !annotator_is_enabled() )
    {
        _fatal_error( "CoreNLP annotator is not enabled in the configuration." );
    }

    my $annotation_exists = undef;
    eval { $annotation_exists = $_gridfs_store->content_exists( $db, $stories_id ); };
    if ( $@ )
    {
        die "GridFS died while testing whether or not an annotation exists for story $stories_id: $@";
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

# Run the CoreNLP annotation for the story, store results in MongoDB
# If story is already annotated, issue a warning and overwrite
# Return 1 on success, 0 on failure, die() on error, exit() on fatal error
sub store_annotation_for_story($$)
{
    my ( $db, $stories_id ) = @_;

    if ( !annotator_is_enabled() )
    {
        _fatal_error( "CoreNLP annotator is not enabled in the configuration." );
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
    eval { $json_annotation = _encode_json( \%annotations ); };
    if ( $@ or ( !$json_annotation ) )
    {
        _fatal_error( "Unable to encode hashref to JSON: $@\nHashref: " . Dumper( $json_annotation ) );
        return 0;
    }

    say STDERR "Done annotating sentences and story text for story $stories_id.";
    say STDERR 'JSON length: ' . length( $json_annotation );

    say STDERR "Storing annotation results to GridFS for story $stories_id...";

    # Write to GridFS, index by stories_id
    eval {
        my $param_skip_encode_and_compress  = 0;                               # objects should be compressed...
        my $param_use_bzip2_instead_of_gzip = CORENLP_GRIDFS_USE_BZIP2 + 0;    # ...with Bzip2

        my $path = $_gridfs_store->store_content(
            $db, $stories_id, \$json_annotation,
            $param_skip_encode_and_compress,
            $param_use_bzip2_instead_of_gzip
        );
    };
    if ( $@ )
    {
        _fatal_error( "Unable to store CoreNLP annotation result to GridFS: $@" );
        return 0;
    }
    say STDERR "Done storing annotation results to GridFS for story $stories_id.";

    return 1;
}

# Fetch the CoreNLP annotation JSON from MongoDB for the story
# Return string JSON on success, undef if the annotation doesn't exist in MongoDB, die() on error
sub fetch_annotation_json_for_story($$)
{
    my ( $db, $stories_id ) = @_;

    if ( !annotator_is_enabled() )
    {
        die "CoreNLP annotator is not enabled in the configuration.";
    }

    unless ( story_is_annotated( $db, $stories_id ) )
    {
        warn "Story $stories_id is not annotated with CoreNLP.";
        return undef;
    }

    my $annotation;
    eval { $annotation = _fetch_annotation_from_gridfs_for_story( $db, $stories_id ); };
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
    eval { $story_annotation_json = _encode_json( $story_annotation, 1 ); };
    if ( $@ or ( !$story_annotation_json ) )
    {
        die "Unable to encode story annotation to JSON for story $stories_id: $@\nHashref: " . Dumper( $story_annotation );
    }

    return $story_annotation_json;
}

# Fetch the CoreNLP annotation JSON from MongoDB for the story sentence
# Return string JSON on success, undef if the annotation doesn't exist in MongoDB, die() on error
sub fetch_annotation_json_for_story_sentence($$)
{
    my ( $db, $story_sentences_id ) = @_;

    if ( !annotator_is_enabled() )
    {
        die "CoreNLP annotator is not enabled in the configuration.";
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
    eval { $annotation = _fetch_annotation_from_gridfs_for_story( $db, $stories_id ); };
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
    eval { $story_sentence_annotation_json = _encode_json( $story_sentence_annotation, 1 ); };
    if ( $@ or ( !$story_sentence_annotation_json ) )
    {
        die "Unable to encode sentence annotation to JSON for story sentence " .
          $story_sentences_id . ", story $stories_id: $@\nHashref: " . Dumper( $story_sentence_annotation );
    }

    return $story_sentence_annotation_json;
}

# Fetch the CoreNLP annotation JSON from MongoDB for the story and all its sentences
# Annotation for the concatenation of all sentences will have a key of sentences_concatenation_index(), e.g.:
#
# {
#     '_' => { 'corenlp' => 'annotation of the concatenation of all story sentences' },
#     1 => { 'corenlp' => 'annotation of the sentence with story_sentences_id => 1' },
#     2 => { 'corenlp' => 'annotation of the sentence with story_sentences_id => 2' },
#     3 => { 'corenlp' => 'annotation of the sentence with story_sentences_id => 3' },
#     ...
# }
#
# Return string JSON on success, undef if the annotation doesn't exist in MongoDB, die() on error
sub fetch_annotation_json_for_story_and_all_sentences($$)
{
    my ( $db, $stories_id ) = @_;

    if ( !annotator_is_enabled() )
    {
        die "CoreNLP annotator is not enabled in the configuration.";
    }

    unless ( story_is_annotated( $db, $stories_id ) )
    {
        warn "Story $stories_id is not annotated with CoreNLP.";
        return undef;
    }

    my $annotation;
    eval { $annotation = _fetch_annotation_from_gridfs_for_story( $db, $stories_id ); };
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
    eval { $annotation_json = _encode_json( $annotation, 1 ); };
    if ( $@ or ( !$annotation_json ) )
    {
        die "Unable to encode story and its sentences annotation to JSON for story " .
          $stories_id . ": $@\nHashref: " . Dumper( $annotation );
    }

    return $annotation_json;
}

1;
