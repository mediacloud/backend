package MediaWords::Util::Annotator::AnnotatorRole;

#
# Abstract JSON annotator role
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose::Role;

# Returns true if annotator is enabled (via configuration or some other means)
requires 'annotator_is_enabled';

# Returns PostgreSQL table name for storing raw compressed annotations
requires '_postgresql_raw_annotations_table';

# Returns request (MediaWords::Util::Web::UserAgent::Request) that should be
# made to the annotator service to annotate a given text
requires '_request_for_text';

# Returns true if response (JSON decoded into hashref / arrayref) is valid
requires '_fetched_annotation_is_valid';

# Returns arrayref of tags
# (MediaWords::Util::Annotator::AnnotatorTag objects) for raw annotation
# (JSON decoded into hashref / arrayref)
requires '_tags_for_annotation';

# Postprocess response (JSON decoded into hashref / arrayref) just fetched from
# API; might be overridden
sub _postprocess_fetched_annotation($$)
{
    my ( $self, $response ) = @_;
    return $response;
}

# Postprocess response (JSON decoded into hashref / arrayref) just loaded from
# the object store; might be overridden
sub _preprocess_stored_annotation($$)
{
    my ( $self, $response ) = @_;
    return $response;
}

# ---

use Data::Dumper;
use Encode;
use HTTP::Status qw(:constants);
use Readonly;
use Scalar::Defer;
use URI;

use MediaWords::KeyValueStore::PostgreSQL;
use MediaWords::Util::Annotator::AnnotatorTag;
use MediaWords::Util::Process;
use MediaWords::Util::JSON;
use MediaWords::Util::Web;
use MediaWords::Util::Config;
use MediaWords::Util::Text;

# HTTP timeout for annotator
Readonly my $ANNOTATOR_HTTP_TIMEOUT => 600;

# Requested text length limit (0 for no limit)
Readonly my $ANNOTATOR_TEXT_LENGTH_LIMIT => 50 * 1024;

# Store / fetch JSON annotations using Bzip2 compression
Readonly my $ANNOTATOR_USE_BZIP2 => 1;

# PostgreSQL key-value store
has '_postgresql_store' => ( is => 'rw', isa => 'MediaWords::KeyValueStore::PostgreSQL' );

# (Lazy-initialized) PostgreSQL key-value store for storing raw annotations
sub BUILD
{
    my $self = shift;

    my $kvs_table_name = $self->_postgresql_raw_annotations_table();
    unless ( $kvs_table_name )
    {
        fatal_error( "Annotator's key-value store table name is not set." );
    }

    my $compression_method = $MediaWords::KeyValueStore::COMPRESSION_GZIP;
    if ( $ANNOTATOR_USE_BZIP2 )
    {
        $compression_method = $MediaWords::KeyValueStore::COMPRESSION_BZIP2;
    }

    # PostgreSQL storage
    my $postgresql_store = MediaWords::KeyValueStore::PostgreSQL->new(
        {
            table              => $kvs_table_name,        #
            compression_method => $compression_method,    #
        }
    );
    TRACE "Will read / write annotator results to PostgreSQL table: $kvs_table_name";

    $self->_postgresql_store( $postgresql_store );
}

# Fetch JSON annotation for text, decode it into hashref / arrayref
sub _annotate_text($$)
{
    my ( $self, $text ) = @_;

    DEBUG "Annotating " . bytes::length( $text ) . " bytes of text...";

    unless ( defined $text )
    {
        fatal_error( "Text is undefined." );
    }
    unless ( $text )
    {
        # Annotators accept empty strings, but that might happen with some
        # stories so we're just die()ing here
        die "Text is empty.";
    }

    # Trim the text because that's what the annotator will do, and
    # if the text is empty, we want to fail early without making a request
    # to the annotator at all
    $text =~ s/^\s+|\s+$//g;

    if ( $ANNOTATOR_TEXT_LENGTH_LIMIT > 0 )
    {
        my $text_length = length( $text );
        if ( $text_length > $ANNOTATOR_TEXT_LENGTH_LIMIT )
        {
            WARN "Text length ($text_length) has exceeded the request text " .
              "length limit ($ANNOTATOR_TEXT_LENGTH_LIMIT) so I will truncate it.";
            $text = substr( $text, 0, $ANNOTATOR_TEXT_LENGTH_LIMIT );
        }
    }

    unless ( MediaWords::Util::Text::is_valid_utf8( $text ) )
    {
        # Text will be encoded to JSON, so we test the UTF-8 validity before doing anything else
        die "Text is not a valid UTF-8 file: $text";
    }

    # Make a request
    my $ua = MediaWords::Util::Web::UserAgent->new();
    $ua->set_timing( [ 1, 2, 4, 8 ] );
    $ua->set_timeout( $ANNOTATOR_HTTP_TIMEOUT );
    $ua->set_max_size( undef );

    my $request;
    eval { $request = $self->_request_for_text( $text ); };
    if ( $@ or ( !$request ) )
    {
        # Assume that this is some sort of a programming error too
        fatal_error( "Unable to create annotator request for text '$text'" );
    }

    TRACE "Sending request to " . $request->url() . "...";
    my $response = $ua->request( $request );
    TRACE "Response received.";

    # Force UTF-8 encoding on the response because the server might not always
    # return correct "Content-Type"
    my $results_string = $response->decoded_utf8_content(
        charset         => 'utf8',
        default_charset => 'utf8'
    );

    unless ( $response->is_success )
    {
        # Error; determine whether we should be blamed for making a malformed
        # request, or is it an extraction error

        DEBUG "Request failed: " . $response->decoded_content;

        if ( lc( $response->status_line ) eq '500 read timeout' )
        {
            # die() on request timeouts without retrying anything
            # because those usually mean that we posted something funky
            # to the annotator service and it got stuck
            LOGCONFESS "The request timed out, giving up; text length: " . bytes::length( $text ) . "; text: $text";
        }

        if ( $response->error_is_client_side() )
        {
            # Error was generated by the user agent client code; likely didn't reach server
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
                # Processing error -- die() so that the error gets caught and logged into a database
                die 'Annotator service was unable to process the download: ' . $results_string;

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
        die "Annotator returned nothing for text: " . $text;
    }

    # Parse resulting JSON
    DEBUG "Parsing response's JSON...";
    my $results_hashref;
    eval { $results_hashref = MediaWords::Util::JSON::decode_json( $results_string ); };
    if ( $@ or ( !ref $results_hashref ) )
    {
        # If the JSON is invalid, it's probably something broken with the
        # remote service, so that's why whe do fatal_error() here
        fatal_error( "Unable to parse JSON response: $@\nJSON string: $results_string" );
    }
    DEBUG "Done parsing response's JSON.";

    my $response_is_valid;

    eval { $response_is_valid = $self->_fetched_annotation_is_valid( $results_hashref ); };
    if ( $@ or ( !defined( $response_is_valid ) ) )
    {
        fatal_error( "Unable to determine whether reponse is valid for JSON response: $results_string" );
    }
    unless ( $response_is_valid )
    {
        fatal_error( "Annotator response is invalid for JSON response: $results_string" );
    }

    eval { $results_hashref = $self->_postprocess_fetched_annotation( $results_hashref ); };
    if ( $@ or ( !$results_hashref ) )
    {
        fatal_error( "Unable to postprocess fetched response for JSON response: $results_string" );
    }

    DEBUG "Done annotating " . bytes::length( $text ) . " bytes of text.";

    return $results_hashref;
}

# Check if story can be annotated
# Return 1 if story can be annotated, 0 otherwise, die() on error, exit() on fatal error
sub story_is_annotatable($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    unless ( $self->annotator_is_enabled() )
    {
        die "Annotator is not enabled in the configuration.";
    }

    my $story = $db->query(
        <<EOF,
        SELECT story_is_english_and_has_sentences
        FROM story_is_english_and_has_sentences(?)
EOF
        $stories_id
    )->hash;
    if ( $story->{ story_is_english_and_has_sentences } )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Check if story is annotated
# Return 1 if story is annotated, 0 otherwise, die() on error, exit() on fatal error
sub story_is_annotated($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    unless ( $self->annotator_is_enabled() )
    {
        die "Annotator is not enabled in the configuration.";
    }

    my $annotation_exists = undef;
    eval { $annotation_exists = $self->_postgresql_store()->content_exists( $db, $stories_id ); };
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

# Run the annotation for the story, store results in key-value store
# If story is already annotated, issue a warning and overwrite
# Return 1 on success, 0 on failure, die() on error, exit() on fatal error
sub annotate_and_store_for_story($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    unless ( $self->annotator_is_enabled() )
    {
        fatal_error( "Annotator is not enabled in the configuration." );
    }

    if ( $self->story_is_annotated( $db, $stories_id ) )
    {
        WARN "Story $stories_id is already annotated, so I will overwrite it.";
    }

    unless ( $self->story_is_annotatable( $db, $stories_id ) )
    {
        WARN "Story $stories_id is not annotatable.";
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

    # Annotate concatenation of all sentences
    INFO "Annotating story's $stories_id concatenated sentences...";
    my $sentences_concat_text = join( ' ', map { $_->{ sentence } } @{ $story_sentences } );
    my $annotation = $self->_annotate_text( $sentences_concat_text );
    unless ( $annotation )
    {
        die "Unable to annotate story sentences concatenation for story $stories_id.\n";
    }

    # Convert results to a minimized JSON
    my $json_annotation;
    eval { $json_annotation = MediaWords::Util::JSON::encode_json( $annotation ); };
    if ( $@ or ( !$json_annotation ) )
    {
        fatal_error( "Unable to encode hashref to JSON: $@\nHashref: " . Dumper( $json_annotation ) );
        return 0;
    }
    INFO "Done annotating story's $stories_id concatenated sentences.";

    DEBUG 'JSON length: ' . length( $json_annotation );

    INFO "Storing annotation results for story $stories_id...";

    # Write to PostgreSQL, index by stories_id
    eval { $self->_postgresql_store()->store_content( $db, $stories_id, \$json_annotation ); };
    if ( $@ )
    {
        fatal_error( "Unable to store annotation result: $@" );
        return 0;
    }
    INFO "Done storing annotation results for story $stories_id.";

    return 1;
}

# Fetch the annotation from key-value store for the story
#
# Return hashref with annotation success, undef if the annotation doesn't exist in any
# key-value stores, die() on error
sub fetch_annotation_for_story($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    unless ( $self->annotator_is_enabled() )
    {
        fatal_error( "Annotator is not enabled in the configuration." );
    }

    unless ( $self->story_is_annotated( $db, $stories_id ) )
    {
        WARN "Story $stories_id is not annotated.";
        return undef;
    }

    # Fetch annotation
    my $json_ref          = undef;
    my $param_object_path = undef;    # no such thing, objects are indexed by filename
    eval { $json_ref = $self->_postgresql_store()->fetch_content( $db, $stories_id, $param_object_path ); };
    if ( $@ or ( !defined $json_ref ) )
    {
        die "Store died while fetching annotation for story $stories_id: $@\n";
    }

    my $json = $$json_ref;
    unless ( $json )
    {
        die "Fetched annotation is undefined or empty for story $stories_id.\n";
    }

    my $annotation;
    eval { $annotation = MediaWords::Util::JSON::decode_json( $json ); };
    if ( $@ or ( !ref $annotation ) )
    {
        die "Unable to parse annotation JSON for story $stories_id: $@\nString JSON: $json";
    }

    eval { $annotation = $self->_preprocess_stored_annotation( $annotation ); };
    if ( $@ or ( !$annotation ) )
    {
        fatal_error( "Unable to preprocess stored annotation: $@\nString JSON: $json" );
    }

    return $annotation;
}

sub _strip_linebreaks_and_whitespace($)
{
    my $string = shift;

    # Tag name can't contain linebreaks
    $string =~ s/[\r\n]/ /g;
    $string =~ s/\s\s*/ /g;
    $string =~ s/^\s+|\s+$//g;

    return $string;
}

# Add version, country and story tags for story
sub update_tags_for_story($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    unless ( $self->annotator_is_enabled() )
    {
        fatal_error( "Annotator is not enabled in the configuration." );
    }

    my $config = MediaWords::Util::Config::get_config();

    my $annotation = $self->fetch_annotation_for_story( $db, $stories_id );
    unless ( $annotation )
    {
        die "Unable to fetch annotation for story $stories_id";
    }

    my $tags;
    eval { $tags = $self->_tags_for_annotation( $annotation ); };
    if ( $@ or ( !$tags ) )
    {
        # Programming error (should at least return an empty arrayref)
        fatal_error( "Unable to fetch tags for story $stories_id: $@" );
    }

    TRACE "Tags for story $stories_id: " . Dumper( $tags );

    $db->begin;

    foreach my $tag ( @{ $tags } )
    {
        unless ( ref( $tag ) eq 'MediaWords::Util::Annotator::AnnotatorTag' )
        {
            fatal_error( "Tag is not of MediaWords::Util::Annotator::AnnotatorTag type" );
        }

        my $tag_sets_name = _strip_linebreaks_and_whitespace( $tag->tag_sets_name() );

        # Delete old tags the story might have under a given tag set
        $db->query(
            <<SQL,
            DELETE FROM stories_tags_map
                USING tags, tag_sets
            WHERE stories_tags_map.tags_id = tags.tags_id
              AND tags.tag_sets_id = tag_sets.tag_sets_id
              AND stories_tags_map.stories_id = ?
              AND tag_sets.name = ?
SQL
            $stories_id, $tag_sets_name
        );
    }

    foreach my $tag ( @{ $tags } )
    {
        my $tag_sets_name = _strip_linebreaks_and_whitespace( $tag->tag_sets_name() );
        my $tags_name     = _strip_linebreaks_and_whitespace( $tag->tags_name() );

        # Not using find_or_create() because tag set / tag might already exist
        # with slightly different label / description

        # Create tag set
        my $db_tag_set = $db->select( 'tag_sets', '*', { name => $tag_sets_name } )->hash;
        unless ( $db_tag_set )
        {
            $db->query(
                <<SQL,
                INSERT INTO tag_sets (name, label, description)
                VALUES (?, ?, ?)
                ON CONFLICT (name) DO NOTHING
SQL
                $tag_sets_name, $tag->tag_sets_label(), $tag->tag_sets_description()
            );
            $db_tag_set = $db->select( 'tag_sets', '*', { name => $tag_sets_name } )->hash;
        }
        my $tag_sets_id = $db_tag_set->{ tag_sets_id };

        # Create tag
        my $db_tag = $db->select( 'tags', '*', { tag_sets_id => $tag_sets_id, tag => $tags_name } )->hash;
        unless ( $db_tag )
        {
            $db->query(
                <<SQL,
                INSERT INTO tags (tag_sets_id, tag, label, description)
                VALUES (?, ?, ?, ?)
                ON CONFLICT (tag, tag_sets_id) DO NOTHING
SQL
                $tag_sets_id, $tags_name, $tag->tags_label(), $tag->tags_description()
            );
            $db_tag = $db->select( 'tags', '*', { tag_sets_id => $tag_sets_id, tag => $tags_name } )->hash;
        }
        my $tags_id = $db_tag->{ tags_id };

        # Assign story to tag (if no such mapping exists yet)
        $db->query(
            <<SQL,
            INSERT INTO stories_tags_map (stories_id, tags_id)
            VALUES (?, ?)
                ON CONFLICT (stories_id, tags_id) DO NOTHING
SQL
            $stories_id, $tags_id
        );
    }

    $db->commit;
}

1;
