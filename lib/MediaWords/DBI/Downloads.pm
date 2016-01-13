package MediaWords::DBI::Downloads;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various helper functions for downloads

use strict;
use warnings;

use Carp;
use Scalar::Defer;
use Readonly;

use MediaWords::Crawler::Extractor;
use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::DB;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::StoryVectors;
use MediaWords::Util::Paths;
use MediaWords::Util::ExtractorFactory;
use MediaWords::Util::HeuristicExtractor;
use MediaWords::GearmanFunction::AnnotateWithCoreNLP;
use MediaWords::Util::ThriftExtractor;

# Database inline content length limit
Readonly my $INLINE_CONTENT_LENGTH => 256;

my $_block_level_element_tags = [
    qw ( h1 h2 h3 h4 h5 h6 p div dl dt dd ol ul li dir menu
      address blockquote center div hr ins noscript pre )
];

my $tag_list = join '|', ( map { quotemeta $_ } ( @{ $_block_level_element_tags } ) );

my $_block_level_start_tag_re = qr{
                   < (:? $tag_list ) (:? > | \s )
           }ix
  ;

my $_block_level_end_tag_re = qr{
                   </ (:? $tag_list ) >
           }ix
  ;

sub _contains_block_level_tags
{
    my ( $string ) = @_;

    if ( $string =~ $_block_level_start_tag_re )
    {
        return 1;
    }

    if ( $string =~ $_block_level_end_tag_re )
    {
        return 1;
    }

    return 0;
}

sub _new_lines_around_block_level_tags
{
    my ( $string ) = @_;

    #say STDERR "_new_lines_around_block_level_tags '$string'";

    return $string if ( !_contains_block_level_tags( $string ) );

    $string =~ s{
       ( $_block_level_start_tag_re
      )
      }
      {\n\n$1}gsxi;

    $string =~ s{
       (
$_block_level_end_tag_re
     )
     }
     {$1\n\n}gsxi;

    #say STDERR "_new_lines_around_block_level_tags '$string'";

    #exit;

    #$string = 'sddd';

    return $string;

}

sub _get_extracted_html
{
    my ( $lines, $included_lines ) = @_;

    my $is_line_included = { map { $_ => 1 } @{ $included_lines } };

    my $config                                      = MediaWords::Util::Config::get_config;
    my $dont_add_double_new_line_for_block_elements = 0;

    my $extracted_html = '';

    # This variable is used to make sure we don't add unnecessary double newlines
    my $previous_concated_line_was_story = 0;

    for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    {
        if ( $is_line_included->{ $i } )
        {
            my $line_text;

            $previous_concated_line_was_story = 1;

            $line_text = $lines->[ $i ];

            #_new_lines_around_block_level_tags( $lines->[ $i ] );

            $extracted_html .= ' ' . $line_text;
        }
        elsif ( _contains_block_level_tags( $lines->[ $i ] ) )
        {
            ## '\n\n\ is used as a sentence splitter so no need to add it more than once between text lines
            if ( $previous_concated_line_was_story )
            {

                # Add double newline bc/ it will be recognized by the sentence splitter as a sentence boundary.
                $extracted_html .= "\n\n";

                $previous_concated_line_was_story = 0;
            }
        }
    }

    return $extracted_html;
}

# Inline download store
# (downloads.path is prefixed with "content:", download is stored in downloads.path itself)
my $_store_inline = lazy
{
    require MediaWords::KeyValueStore::DatabaseInline;

    return MediaWords::KeyValueStore::DatabaseInline->new();
};

# Amazon S3 download store
# (downloads.path is prefixed with "amazon_s3:", download is stored in Amazon S3)
my $_store_amazon_s3 = lazy
{
    require MediaWords::KeyValueStore::AmazonS3;
    require MediaWords::KeyValueStore::CachedAmazonS3;

    my $config = MediaWords::Util::Config::get_config;

    unless ( $config->{ amazon_s3 } )
    {
        say STDERR "Amazon S3 download store is not configured.";
        return undef;
    }

    my $store_package_name = 'MediaWords::KeyValueStore::AmazonS3';
    my $cache_root_dir     = undef;
    if ( $config->{ mediawords }->{ cache_s3_downloads } eq 'yes' )
    {
        $store_package_name = 'MediaWords::KeyValueStore::CachedAmazonS3';
        $cache_root_dir     = $config->{ mediawords }->{ data_dir } . '/cache/s3_downloads';
    }

    return $store_package_name->new(
        {
            access_key_id     => $config->{ amazon_s3 }->{ downloads }->{ access_key_id },
            secret_access_key => $config->{ amazon_s3 }->{ downloads }->{ secret_access_key },
            bucket_name       => $config->{ amazon_s3 }->{ downloads }->{ bucket_name },
            directory_name    => $config->{ amazon_s3 }->{ downloads }->{ directory_name },
            cache_root_dir    => $cache_root_dir,
        }
    );
};

# PostgreSQL download store
# (downloads.path is prefixed with "postgresql:", download is stored in "raw_downloads" table)
my $_store_postgresql = lazy
{
    require MediaWords::KeyValueStore::PostgreSQL;
    require MediaWords::KeyValueStore::MultipleStores;

    my $config = MediaWords::Util::Config::get_config;

    # Main raw downloads database / table
    my $raw_downloads_db_label = 'raw_downloads';    # as set up in mediawords.yml
    unless ( grep { $_ eq $raw_downloads_db_label } MediaWords::DB::get_db_labels() )
    {
        #say STDERR "No such label '$raw_downloads_db_label', falling back to default database";
        $raw_downloads_db_label = undef;
    }

    my $postgresql_store = MediaWords::KeyValueStore::PostgreSQL->new(
        {
            database_label => $raw_downloads_db_label,                         #
            table => ( $raw_downloads_db_label ? undef : 'raw_downloads' ),    #
        }
    );

    # Add Amazon S3 fallback storage if needed
    if ( lc( $config->{ mediawords }->{ fallback_postgresql_downloads_to_s3 } eq 'yes' ) )
    {
        my $amazon_s3_store = force $_store_amazon_s3;
        unless ( defined $amazon_s3_store )
        {
            croak "'fallback_postgresql_downloads_to_s3' is enabled, but Amazon S3 download storage is not set up.";
        }

        my $postgresql_then_s3_store = MediaWords::KeyValueStore::MultipleStores->new(
            {
                stores_for_reading => [ $postgresql_store, $amazon_s3_store ],
                stores_for_writing => [ $postgresql_store ], # where to write is defined by "download_storage_locations"
            }
        );
        return $postgresql_then_s3_store;
    }
    else
    {
        return $postgresql_store;
    }
};

# (Multi)store for writing downloads
my $_store_for_writing_non_inline_downloads = lazy
{
    require MediaWords::KeyValueStore::MultipleStores;

    my $config = MediaWords::Util::Config::get_config;

    my @stores_for_writing;

    # Early sanity check on configuration
    my $download_storage_locations = $config->{ mediawords }->{ download_storage_locations };
    if ( scalar( @{ $download_storage_locations } ) == 0 )
    {
        croak "No download stores are configured.";
    }

    foreach my $location ( @{ $download_storage_locations } )
    {
        $location = lc( $location );
        my $store;

        if ( $location eq 'databaseinline' )
        {
            croak "$location is not valid for storage";

        }
        elsif ( $location eq 'postgresql' )
        {
            $store = force $_store_postgresql;

        }
        elsif ( $location eq 's3' or $location eq 'amazon_s3' )
        {
            $store = force $_store_amazon_s3;

        }
        else
        {
            croak "Store location '$location' is not valid.";

        }

        unless ( defined $store )
        {
            croak "Store for location '$location' is not configured.";
        }

        push( @stores_for_writing, $store );
    }

    return MediaWords::KeyValueStore::MultipleStores->new( { stores_for_writing => \@stores_for_writing, } );
};

# Returns store for writing new downloads to
sub _download_store_for_writing($)
{
    my $content_ref = shift;

    if ( length( $$content_ref ) < $INLINE_CONTENT_LENGTH )
    {
        # Inline store
        return force $_store_inline;
    }
    else
    {
        # All the rest of the stores
        return force $_store_for_writing_non_inline_downloads;
    }
}

# Returns store to try fetching download from
sub _download_store_for_reading($)
{
    my $download = shift;

    my $download_store;

    my $path = $download->{ path };
    unless ( $path )
    {
        croak "Download path is not set for download $download->{ downloads_id }";
    }

    if ( $path =~ /^([\w]+):/ )
    {
        Readonly my $location => lc( $1 );

        if ( $location eq 'content' )
        {
            $download_store = force $_store_inline;
        }

        elsif ( $location eq 'postgresql' )
        {
            $download_store = force $_store_postgresql;
        }

        elsif ( $location eq 's3' or $location eq 'amazon_s3' )
        {
            $download_store = force $_store_amazon_s3;
        }

        elsif ( $location eq 'gridfs' or $location eq 'tar' )
        {
            # Might get later overriden to "amazon_s3"
            $download_store = force $_store_postgresql;
        }

        else
        {
            croak "Download location '$location' is unknown for download $download->{ downloads_id }";
        }
    }
    else
    {
        # Assume it's stored in a filesystem (the downloads.path contains a
        # full path to the download).
        #
        # Those downloads have been migrated to PostgreSQL (which might get redirected to S3).
        $download_store = force $_store_postgresql;
    }

    unless ( defined $download_store )
    {
        croak "Download store is undefined for download " . $download->{ downloads_id };
    }

    my $config = MediaWords::Util::Config::get_config;

    # All non-inline downloads have to be fetched from S3?
    if ( $download_store ne force $_store_inline
        and lc( $config->{ mediawords }->{ read_all_downloads_from_s3 } ) eq 'yes' )
    {
        $download_store = force $_store_amazon_s3;
    }

    unless ( $download_store )
    {
        croak "Download store is not configured for download " . $download->{ downloads_id };
    }

    return $download_store;
}

# fetch the content for the given download as a content_ref
sub fetch_content($$)
{
    my ( $db, $download ) = @_;

    unless ( exists $download->{ downloads_id } )
    {
        croak "fetch_content called with invalid download";
    }

    unless ( download_successful( $download ) )
    {
        confess "attempt to fetch content for unsuccessful download $download->{ downloads_id }  / $download->{ state }";
    }

    my $store = _download_store_for_reading( $download );
    unless ( $store )
    {
        croak "No store for reading download " . $download->{ downloads_id };
    }

    # Fetch content
    my $content_ref = $store->fetch_content( $db, $download->{ downloads_id }, $download->{ path } );
    unless ( $content_ref and ref( $content_ref ) eq 'SCALAR' )
    {
        croak "Unable to fetch content for download " . $download->{ downloads_id } . "; tried store: " . ref( $store );
    }

    # horrible hack to fix old content that is not stored in unicode
    my $config                  = MediaWords::Util::Config::get_config;
    my $ascii_hack_downloads_id = $config->{ mediawords }->{ ascii_hack_downloads_id };
    if ( $ascii_hack_downloads_id and ( $download->{ downloads_id } < $ascii_hack_downloads_id ) )
    {
        $$content_ref =~ s/[^[:ascii:]]/ /g;
    }

    return $content_ref;
}

# return content as lines in an array after running through the extractor preprocessor
sub _preprocess_content_lines($)
{
    my ( $content_ref ) = @_;

    my $lines = [ split( /[\n\r]+/, $$content_ref ) ];

    $lines = MediaWords::Crawler::Extractor::preprocess( $lines );

    return $lines;
}

# fetch the content as lines in an array after running through the extractor preprocessor
sub fetch_preprocessed_content_lines($$)
{
    my ( $db, $download ) = @_;

    my $content_ref = fetch_content( $db, $download );

    # print "CONTENT:\n**\n${ $content_ref }\n**\n";

    unless ( $content_ref )
    {
        warn( "unable to find content: " . $download->{ downloads_id } );
        return [];
    }

    return _preprocess_content_lines( $content_ref );
}

# run MediaWords::Crawler::Extractor against the download content and return a hash in the form of:
# { extracted_html => $html,    # a string with the extracted html
#   extracted_text => $text,    # a string with the extracted html strippped to text
#   download_lines => $lines,   # (optional) an array of the lines of original html
#   scores => $scores }         # (optional) the scores returned by Mediawords::Crawler::Extractor::score_lines
sub extractor_results_for_download($$)
{
    my ( $db, $download ) = @_;

    my $content_ref = fetch_content( $db, $download );

    # FIXME if we're using Readability extractor, there's no point fetching
    # story title and description as Readability doesn't use it
    my $story = $db->find_by_id( 'stories', $download->{ stories_id } );

    return extract_content_ref( $content_ref, $story->{ title }, $story->{ description } );
}

# if the given line looks like a tagline for another story and is missing an ending period, add a period
#
sub add_period_to_tagline($$$)
{
    my ( $lines, $scores, $i ) = @_;

    if ( ( $i < 1 ) || ( $i >= ( @{ $lines } - 1 ) ) )
    {
        return;
    }

    if ( $scores->[ $i - 1 ]->{ is_story } || $scores->[ $i + 1 ]->{ is_story } )
    {
        return;
    }

    if ( $lines->[ $i ] =~ m~[^\.]\s*</[a-z]+>$~i )
    {
        $lines->[ $i ] .= '.';
    }
}

# Extract content referenced by $content_ref
sub extract_content_ref($$$;$)
{
    my ( $content_ref, $story_title, $story_description, $extractor_method ) = @_;

    unless ( $extractor_method )
    {
        my $config = MediaWords::Util::Config::get_config;
        $extractor_method = $config->{ mediawords }->{ extractor_method };
    }

    my $extracted_html;
    my $ret = {};

    # Don't run through expensive extractor if the content is short and has no html
    if ( ( length( $$content_ref ) < 4096 ) and ( $$content_ref !~ /\<.*\>/ ) )
    {
        $ret = {
            extracted_html => $$content_ref,
            extracted_text => $$content_ref,
        };
    }
    else
    {
        #say STDERR "DBI::Downloads::extractor_results_for_download extractor_method $extractor_method";

        if ( $extractor_method eq 'PythonReadability' )
        {
            $extracted_html = MediaWords::Util::ThriftExtractor::get_extracted_html( $$content_ref );
        }
        elsif ( $extractor_method eq 'HeuristicExtractor' )
        {
            my $lines = _preprocess_content_lines( $content_ref );

            # print "PREPROCESSED LINES:\n**\n" . join( "\n", @{ $lines } ) . "\n**\n";

            $ret = extract_preprocessed_lines_for_story( $lines, $story_title, $story_description );

            my $download_lines        = $ret->{ download_lines };
            my $included_line_numbers = $ret->{ included_line_numbers };

            $extracted_html = _get_extracted_html( $download_lines, $included_line_numbers );
        }
        else
        {
            die "invalid extractor method: $extractor_method";
        }

        $extracted_html = _new_lines_around_block_level_tags( $extracted_html );
        my $extracted_text = html_strip( $extracted_html );

        $ret->{ extracted_html } = $extracted_html;
        $ret->{ extracted_text } = $extracted_text;
    }

    return $ret;
}

sub extract_preprocessed_lines_for_story($$$)
{
    my ( $lines, $story_title, $story_description ) = @_;

    my $old_extractor = MediaWords::Util::ExtractorFactory::createExtractor();

    return $old_extractor->extract_preprocessed_lines_for_story( $lines, $story_title, $story_description );
}

# store the download content in the file system
sub store_content($$$)
{
    my ( $db, $download, $content_ref ) = @_;

    #say STDERR "starting store_content for download $download->{ downloads_id } ";

    my $new_state = 'success';
    if ( $download->{ state } eq 'feed_error' )
    {
        $new_state = $download->{ state };
    }

    # Store content
    my $path = '';
    eval {
        my $store = _download_store_for_writing( $content_ref );
        unless ( defined $store )
        {
            croak "No download store to write to.";
        }

        $path = $store->store_content( $db, $download->{ downloads_id }, $content_ref );
    };
    if ( $@ )
    {
        croak "Error while trying to store download ID " . $download->{ downloads_id } . ':' . $@;
        $new_state = 'error';
        $download->{ error_message } = $@;
    }
    elsif ( $new_state eq 'success' )
    {
        $download->{ error_message } = '';
    }

    # Update database
    $db->query(
        <<"EOF",
        UPDATE downloads
        SET state = ?,
            path = ?,
            error_message = ?,
            file_status = DEFAULT       -- Reset the file_status in case
                                        -- this download is being redownloaded
        WHERE downloads_id = ?
EOF
        $new_state,
        $path,
        $download->{ error_message },
        $download->{ downloads_id }
    );

    $download->{ state } = $new_state;
    $download->{ path }  = $path;

    $download = $db->find_by_id( 'downloads', $download->{ downloads_id } );

    return $download;
}

# try to store content determinedly by retrying on a failed eval at doubling increments up to 32 seconds
sub store_content_determinedly
{
    my ( $db, $download, $content ) = @_;

    my $interval = 1;
    while ( 1 )
    {
        eval { store_content( $db, $download, \$content ) };
        return unless ( $@ );

        if ( $interval < 33 )
        {
            warn( "store_content failed: $@\ntrying again..." );
            $interval *= 2;
            sleep( $interval );
        }
        else
        {
            warn( "store_content_determinedly failed: $@" );
            return;
        }
    }
}

# convenience method to get the media_id for the download
sub get_media_id($$)
{
    my ( $db, $download ) = @_;

    my $feeds_id = $download->{ feeds_id };

    unless ( $feeds_id )
    {
        die "feeds_id is undefined; database error: " . $db->error;
    }

    my $media_id = $db->query( "SELECT media_id from feeds where feeds_id = ?", $feeds_id )->hash->{ media_id };

    unless ( defined $media_id )
    {
        die "Could not get media id for feeds_id '$feeds_id; database error: " . $db->error;
    }

    return $media_id;
}

# convenience method to get the media source for the given download
sub get_medium($$)
{
    my ( $db, $download ) = @_;

    my $media_id = get_media_id( $db, $download );

    my $medium = $db->find_by_id( 'media', $media_id );

    return $medium;
}

sub extract_only( $$ )
{
    my ( $db, $download ) = @_;

    my $download_text = MediaWords::DBI::DownloadTexts::create_from_download( $db, $download );

    #say STDERR "Got download_text";

    return $download_text;
}

sub process_download_for_extractor($$$;$$$)
{
    my ( $db, $download, $process_num, $no_dedup_sentences, $no_vector ) = @_;

    $process_num //= 1;

    my $stories_id = $download->{ stories_id };

    say STDERR "[$process_num] extract: $download->{ downloads_id } $stories_id $download->{ url }";
    my $download_text = MediaWords::DBI::Downloads::extract_only( $db, $download );

    #say STDERR "Got download_text";

    my $has_remaining_download = $db->query(
        <<EOF,
        SELECT downloads_id
        FROM downloads
        WHERE stories_id = ?
          AND extracted = 'f'
          AND type = 'content'
EOF
        $stories_id
    )->hash;

    if ( !( $has_remaining_download ) )
    {
        my $story = $db->find_by_id( 'stories', $stories_id );

        MediaWords::DBI::Stories::process_extracted_story( $story, $db, $no_dedup_sentences, $no_vector );
    }
    elsif ( !( $no_vector ) )
    {

        say STDERR "[$process_num] pending more downloads ...";
    }
}

# Extract and vector the download; on error, store the error message in the
# "downloads" table
sub extract_and_vector
{
    my ( $db, $download, $process_num ) = @_;

    my $no_dedup_sentences = 0;
    my $no_vector          = 0;

    eval { process_download_for_extractor( $db, $download, $process_num, $no_dedup_sentences, $no_vector ); };

    if ( $@ )
    {
        my $downloads_id = $download->{ downloads_id };

        say STDERR "extractor error processing download $downloads_id: $@";

        $db->rollback;

        $db->query(
            <<EOF,
            UPDATE downloads
            SET state = 'extractor_error',
                error_message = ?
            WHERE downloads_id = ?
EOF
            "extractor error: $@", $downloads_id
        );

        $db->commit;

        return 0;
    }

    # Extraction succeeded
    $db->commit;

    return 1;
}

# Return true if the download was downloaded successfully.
# This method is needed because there are cases it which the download was sucessfully downloaded \
# but had a subsequent processing error. e.g. 'extractor_error' and 'feed_error'
sub download_successful
{
    my ( $download ) = @_;

    my $state = $download->{ state };

    return ( $state eq 'success' ) || ( $state eq 'feed_error' ) || ( $state eq 'extractor_error' );
}

1;
