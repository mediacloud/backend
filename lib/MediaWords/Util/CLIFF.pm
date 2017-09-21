package MediaWords::Util::CLIFF;

use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::Util::Process;
use MediaWords::KeyValueStore::PostgreSQL;
use MediaWords::Util::CLIFF::Annotator;

use Readonly;
use Scalar::Defer;
use Data::Dumper;

# PostgreSQL table name for storing raw CLIFF annotations
Readonly my $CLIFF_POSTGRESQL_KVS_TABLE_NAME => 'cliff_annotations';

# Store / fetch downloads using Bzip2 compression
Readonly my $CLIFF_USE_BZIP2 => 1;

# (Lazy-initialized) PostgreSQL key-value store shared by ::Util::CLIFF::* packages
#
# We use a static, package-wide variable here because:
# a) PostgreSQL handler should support being used by multiple threads by now, and
# b) each job worker is a separate process so there shouldn't be any resource clashes.
my $_postgresql_store = lazy
{
    unless ( MediaWords::Util::CLIFF::cliff_is_enabled() )
    {
        fatal_error( "CLIFF annotator is not enabled; why are you accessing this variable?" );
    }

    my $compression_method = $MediaWords::KeyValueStore::COMPRESSION_GZIP;
    if ( $CLIFF_USE_BZIP2 )
    {
        $compression_method = $MediaWords::KeyValueStore::COMPRESSION_BZIP2;
    }

    # PostgreSQL storage
    my $postgresql_store = MediaWords::KeyValueStore::PostgreSQL->new(
        {
            table              => $CLIFF_POSTGRESQL_KVS_TABLE_NAME,    #
            compression_method => $compression_method,                 #
        }
    );
    DEBUG "Will read / write CLIFF annotator results to PostgreSQL table: $CLIFF_POSTGRESQL_KVS_TABLE_NAME";

    return $postgresql_store;
};

# Returns true if CLIFF is enabled
sub cliff_is_enabled()
{
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

# Check if story can be annotated with CLIFF
# Return 1 if story can be annotated, 0 otherwise, die() on error, exit() on fatal error
sub story_is_annotatable($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( MediaWords::Util::CLIFF::cliff_is_enabled() )
    {
        fatal_error( "CLIFF annotator is not enabled in the configuration." );
    }

    my $story = $db->query(
        <<EOF,
        SELECT story_is_annotatable_with_cliff
        FROM story_is_annotatable_with_cliff(?)
EOF
        $stories_id
    )->hash;
    if ( $story->{ story_is_annotatable_with_cliff } )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Check if story is annotated with CLIFF
# Return 1 if story is annotated, 0 otherwise, die() on error, exit() on fatal error
sub story_is_annotated($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( MediaWords::Util::CLIFF::cliff_is_enabled() )
    {
        fatal_error( "CLIFF annotator is not enabled in the configuration." );
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

# Run the CLIFF annotation for the story, store results in key-value store
# If story is already annotated, issue a warning and overwrite
# Return 1 on success, 0 on failure, die() on error, exit() on fatal error
sub annotate_and_store_for_story($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( MediaWords::Util::CLIFF::cliff_is_enabled() )
    {
        fatal_error( "CLIFF annotator is not enabled in the configuration." );
        return 0;
    }

    if ( story_is_annotated( $db, $stories_id ) )
    {
        WARN "Story $stories_id is already annotated with CLIFF, so I will overwrite it.";
    }

    unless ( story_is_annotatable( $db, $stories_id ) )
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
    my $annotation = MediaWords::Util::CLIFF::Annotator::annotate_text( $sentences_concat_text );
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
    eval { $_postgresql_store->store_content( $db, $stories_id, \$json_annotation ); };
    if ( $@ )
    {
        fatal_error( "Unable to store CLIFF annotation result: $@" );
        return 0;
    }
    INFO "Done storing annotation results for story $stories_id.";

    return 1;
}

# Fetch the CLIFF annotation from key-value store for the story
#
# Return hashref with annotation success, undef if the annotation doesn't exist in any
# key-value stores, die() on error
sub fetch_annotation_for_story($$)
{
    my ( $db, $stories_id ) = @_;

    unless ( MediaWords::Util::CLIFF::cliff_is_enabled() )
    {
        LOGCONFESS "CLIFF annotator is not enabled in the configuration.";
    }

    unless ( story_is_annotated( $db, $stories_id ) )
    {
        WARN "Story $stories_id is not annotated with CLIFF.";
        return undef;
    }

    # Fetch annotation
    my $json_ref          = undef;
    my $param_object_path = undef;    # no such thing, objects are indexed by filename
    eval { $json_ref = $_postgresql_store->fetch_content( $db, $stories_id, $param_object_path ); };
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

    return $annotation;
}

1;
