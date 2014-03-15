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

# How to index annotation JSON for the concatenation of all sentences
use constant CORENLP_SENTENCES_CONCAT_INDEX => '_';

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
            _fatal_error( "Invalid CoreNLP annotator URI: $url" );
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
sub _corenlp_annotate($)
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
    my $text_hashref = { 'text' => $text };
    my $text_json = encode_json( $text_hashref );

    # Text has to be encoded because HTTP::Request only accepts bytes as POST data
    my $text_json_encoded;
    eval { $text_json_encoded = Encode::encode_utf8( $text_json ); };
    if ( $@ or ( !$text_json_encoded ) )
    {
        die "Unable to encode_utf8() JSON text to be annotated: $text_json";
    }

    # Make a request
    my $ua = MediaWords::Util::Web::UserAgent;
    $ua->timeout( $_corenlp_annotator_timeout );
    $ua->max_size( undef );

    my $request = HTTP::Request->new( POST => $_corenlp_annotator_url );
    $request->content_type( 'application/json; charset=utf8' );
    $request->content( $text_json_encoded );

    my $response = $ua->request( $request );

    my $results_string;
    if ( $response->is_success )
    {
        # OK
        $results_string = $response->decoded_content;
    }
    else
    {
        # Error; determine whether we should be blamed for making a malformed
        # request, or is it an extraction error

        if ( MediaWords::Util::Web::response_error_is_client_side( $response ) )
        {
            # Error was generated by LWP::UserAgent; likely didn't reach server
            # at all (timeout, unresponsive host, etc.)
            _fatal_error( 'LWP error: ' . $response->status_line . ': ' . $response->decoded_content );

        }
        else
        {
            # Error was generated by server

            my $http_status_code = $response->code;

            if ( $http_status_code == HTTP_METHOD_NOT_ALLOWED or $http_status_code == HTTP_BAD_REQUEST )
            {
                # Not POST, empty POST
                _fatal_error( $response->status_line . ': ' . $response->decoded_content );

            }
            elsif ( $http_status_code == HTTP_INTERNAL_SERVER_ERROR )
            {
                # CRF processing error -- die() so that the error gets caught and logged into a database
                die 'CoreNLP annotator service was unable to process the download: ' . $response->decoded_content;

            }
            else
            {
                # Shutdown the extractor on unconfigured responses
                _fatal_error( 'Unknown HTTP response: ' . $response->status_line . ': ' . $response->decoded_content );
            }
        }
    }

    unless ( $results_string )
    {
        die "CoreNLP annotator returned nothing for text: " . $text;
    }

    # Parse resulting JSON
    my $results_hashref;
    eval { $results_hashref = decode_json $results_string; };
    if ( $@ or ( !ref $results_hashref ) )
    {
        # If the JSON is invalid, it's probably something broken with the
        # remote CoreNLP service, so that's why whe do _fatal_error() here
        _fatal_error( "Unable to parse JSON response: $results_string" );
    }

    # Check sanity
    unless ( exists( $results_hashref->{ corenlp } ) )
    {
        _fatal_error( "Expected root key 'corenlp' doesn't exist in JSON response: $results_string" );
    }
    unless ( scalar( keys( $results_hashref ) ) == 1 )
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
    unless ( scalar( keys( $results_hashref ) ) > 0 )
    {
        _fatal_error( "'corenlp' root key is not expected to be an empty hash in JSON response: $results_string" );
    }

    return $results_hashref;
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

# Run the CoreNLP annotation for the story, store results in MongoDB
# Return 1 on success, die()s on error, exit()s on fatal error
sub annotate_stories_id($$)
{
    my ( $db, $stories_id ) = @_;

    if ( !annotator_is_enabled() )
    {
        _fatal_error( "CoreNLP annotator is not enabled in the configuration." );
    }

    my $story = $db->find_by_id( 'stories', $stories_id );
    unless ( $story->{ stories_id } )
    {
        die "Story with ID $stories_id was not found.";
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

    # Annotate each sentence separately, index by story_sentences_id
    foreach my $sentence ( @{ $story_sentences } )
    {
        my $sentence_id     = $sentence->{ story_sentences_id } + 0;
        my $sentence_number = $sentence->{ sentence_number } + 0;
        my $sentence_text   = $sentence->{ sentence };

        say STDERR "Annotating story's $stories_id sentence " . ( $sentence_number + 1 ) . " / " .
          scalar( @{ $story_sentences } ) . "...";
        $annotations{ $sentence_id } = _corenlp_annotate( $sentence_text );
        unless ( defined $annotations{ $sentence_id } )
        {
            die "Unable to annotate story sentence $sentence_id.";
        }
    }

    # Annotate concatenation of all sentences, index as '_'
    my $sentences_concat_text = join( ' ', map { $_->{ sentence } } @{ $story_sentences } );

    say STDERR "Annotating story's $stories_id concatenated sentences...";
    my $concat_index = CORENLP_SENTENCES_CONCAT_INDEX . '';
    $annotations{ $concat_index } = _corenlp_annotate( $sentences_concat_text );
    unless ( $annotations{ $concat_index } )
    {
        die "Unable to annotate story sentences concatenation for story $stories_id.\n";
    }

    # Convert results to a minimized JSON
    my $json_annotation;
    eval { $json_annotation = JSON->new->utf8( 1 )->pretty( 0 )->encode( \%annotations ); };
    if ( $@ or ( !$json_annotation ) )
    {
        _fatal_error( "Unable to encode hashref to JSON: " . Dumper( $json_annotation ) );
        return 0;
    }
    say STDERR 'JSON length: ' . length( $json_annotation );

    # Write to GridFS, index by stories_id
    eval { my $path = $_gridfs_store->store_content( $db, $stories_id, \$json_annotation ); };
    if ( $@ )
    {
        _fatal_error( "Unable to store CoreNLP annotation result to GridFS because: $@" );
        return 0;
    }

    return 1;
}

# Run the CoreNLP annotation for the download, store results in MongoDB
# Return 1 on success, die()s on error, exit()s on fatal error
sub annotate_downloads_id($$)
{
    my ( $db, $downloads_id ) = @_;

    if ( !annotator_is_enabled() )
    {
        _fatal_error( "CoreNLP annotator is not enabled in the configuration." );
    }

    my $download = $db->find_by_id( 'downloads', $downloads_id );
    unless ( $download->{ downloads_id } )
    {
        die "Download with ID $downloads_id was not found.";
    }

    my $stories_id = $download->{ stories_id } + 0;

    return annotate_stories_id( $db, $stories_id );
}

1;
