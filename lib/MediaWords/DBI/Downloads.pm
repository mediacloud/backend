package MediaWords::DBI::Downloads;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various helper functions for downloads

use strict;

use Carp;
use Scalar::Defer;
use Readonly;

use MediaWords::Crawler::Extractor;
use MediaWords::Util::Config qw(get_config);
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
use constant INLINE_CONTENT_LENGTH => 256;

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

# lookup table for download store objects; initialized in BEGIN below
my $_download_store_lookup = lazy
{
    # lazy load these modules because some of them are very expensive to load
    # and are tangentially loaded by indirect module dependency
    require MediaWords::KeyValueStore::AmazonS3;
    require MediaWords::KeyValueStore::DatabaseInline;
    require MediaWords::KeyValueStore::GridFS;
    require MediaWords::KeyValueStore::PostgreSQL;

    my $download_store_lookup = {

        # downloads.path is prefixed with "content:";
        # download is stored in downloads.path itself
        databaseinline => undef,

        # downloads.path is prefixed with "postgresql:";
        # download is stored in "raw_downloads" table
        postgresql => undef,

        # downloads.path is prefixed with "amazon_s3:";
        # download is stored in Amazon S3
        amazon_s3 => undef,    # might remain 'undef' if not configured

        # downloads.path is prefixed with "gridfs:";
        # download is stored in MongoDB GridFS
        gridfs => undef,    # might remain 'undef' if not configured
    };

    # Early sanity check on configuration
    my $download_storage_locations = get_config->{ mediawords }->{ download_storage_locations };
    if ( scalar( @{ $download_storage_locations } ) == 0 )
    {
        die "No download storage methods are configured.\n";
    }

    foreach my $download_storage_location ( @{ $download_storage_locations } )
    {
        my $location = lc( $download_storage_location );

        if ( $location eq 'databaseinline' )
        {
            die "download_storage_location $location is not valid for storage";
        }

        unless ( exists $download_store_lookup->{ $download_storage_location } )
        {
            die "download_storage_location '$download_storage_location' is not valid.";
        }
    }

    my %enabled_download_storage_locations = map { $_ => 1 } @{ $download_storage_locations };

    # Test if all enabled storage locations are also configured
    if ( exists( $enabled_download_storage_locations{ amazon_s3 } ) )
    {
        unless ( get_config->{ amazon_s3 } )
        {
            die "'amazon_s3' storage location is enabled, but Amazon S3 is not configured.\n";
        }
    }
    if ( exists( $enabled_download_storage_locations{ gridfs } ) )
    {
        unless ( get_config->{ mongodb_gridfs } )
        {
            die "'gridfs' storage location is enabled, but MongoDB GridFS is not configured.\n";
        }
    }

    # Initialize key value stores for downloads
    if ( get_config->{ amazon_s3 } )
    {
        $download_store_lookup->{ amazon_s3 } = MediaWords::KeyValueStore::AmazonS3->new(
            {
                bucket_name    => get_config->{ amazon_s3 }->{ downloads }->{ bucket_name },
                directory_name => get_config->{ amazon_s3 }->{ downloads }->{ directory_name }
            }
        );
    }

    $download_store_lookup->{ databaseinline } = MediaWords::KeyValueStore::DatabaseInline->new(
        {
            # no arguments are needed
        }
    );

    if ( get_config->{ mongodb_gridfs } )
    {
        if ( get_config->{ mongodb_gridfs }->{ downloads } )
        {
            $download_store_lookup->{ gridfs } = MediaWords::KeyValueStore::GridFS->new(
                { database_name => get_config->{ mongodb_gridfs }->{ downloads }->{ database_name } } );
        }
    }

    my $raw_downloads_db_label = 'raw_downloads';    # as set up in mediawords.yml

    my $connect_settings;
    my $args;
    unless ( grep { $_ eq $raw_downloads_db_label } MediaWords::DB::get_db_labels() )
    {
        say STDERR "No such label '$raw_downloads_db_label', falling back to default database";
        $raw_downloads_db_label = undef;
    }

    $download_store_lookup->{ postgresql } = MediaWords::KeyValueStore::PostgreSQL->new(
        {
            database_label => $raw_downloads_db_label,    #
        }
    );

    return $download_store_lookup;
};

# Returns arrayref of stores for writing new downloads to
sub _download_stores_for_writing($)
{
    my $content_ref = shift;

    my $stores = [];

    if ( length( $$content_ref ) < INLINE_CONTENT_LENGTH )
    {
        unless ( $_download_store_lookup->{ databaseinline } )
        {
            die "DatabaseInline store is not initialized, although it is required by _download_stores_for_writing().\n";
        }

        # Inline
        #say STDERR "Will store inline.";
        push( @{ $stores }, $_download_store_lookup->{ databaseinline } );
    }
    else
    {
        my $download_storage_locations = get_config->{ mediawords }->{ download_storage_locations };
        foreach my $download_storage_location ( @{ $download_storage_locations } )
        {
            my $store = $_download_store_lookup->{ lc( $download_storage_location ) }
              || die "config value mediawords.download_storage_location '$download_storage_location' is not valid.";

            push( @{ $stores }, $store );
        }
    }

    if ( scalar( @{ $stores } ) == 0 )
    {
        die "No download storage locations are configured.\n";
    }

    return $stores;
}

# Returns stores to try fetching download from
sub _download_stores_for_reading($)
{
    my $download = shift;

    my $download_store;

    my $path = $download->{ path };
    unless ( $path )
    {
        die "Download path is not set for download $download->{ downloads_id }";
    }

    if ( $path =~ /^([\w]+):/ )
    {
        Readonly my $location => lc( $1 );

        if ( $location eq 'content' )
        {
            $download_store = 'databaseinline';
        }

        elsif ( $location eq 'postgresql' )
        {
            $download_store = 'postgresql';
        }

        elsif ( $location eq 'amazon_s3' )
        {
            $download_store = 'amazon_s3';
        }

        elsif ( $location eq 'gridfs' or $location eq 'tar' )
        {
            $download_store = 'gridfs';
        }

        else
        {
            die "Download location '$location' is unknown for download $download->{ downloads_id }";
        }

    }
    else
    {
        # Assume it's stored in a filesystem (the downloads.path contains a
        # full path to the download).
        #
        # Those downloads have been migrated to GridFS.
        $download_store = 'gridfs';
    }

    unless ( defined $download_store )
    {
        die "Download store is undefined for download " . $download->{ downloads_id };
    }

    # Overrides:

    # GridFS downloads have to be fetched from S3?
    if ( $download_store eq 'gridfs' or $download_store eq 'tar' )
    {
        if ( lc( get_config->{ mediawords }->{ read_gridfs_downloads_from_s3 } eq 'yes' ) )
        {
            $download_store = 'amazon_s3';
        }
    }

    unless ( defined $_download_store_lookup->{ $download_store } )
    {
        die "Download store '$download_store' is not initialized for download " . $download->{ downloads_id };
    }

    my @stores = ( $_download_store_lookup->{ $download_store } );
    return \@stores;
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

    my $stores = _download_stores_for_reading( $download );
    unless ( scalar( @{ $stores } ) )
    {
        croak "No stores for reading download " . $download->{ downloads_id };
    }

    # Fetch content
    my $content_ref;
    foreach my $store ( @{ $stores } )
    {
        if ( $store->content_exists( $db, $download->{ downloads_id }, $download->{ path } ) )
        {
            $content_ref = $store->fetch_content( $db, $download->{ downloads_id }, $download->{ path } );
            last;
        }
    }
    unless ( $content_ref and ref( $content_ref ) eq 'SCALAR' )
    {
        croak "Unable to fetch content for download " . $download->{ downloads_id } . "; tried stores: " . Dumper( $stores );
    }

    # horrible hack to fix old content that is not stored in unicode
    my $ascii_hack_downloads_id = get_config->{ mediawords }->{ ascii_hack_downloads_id };
    if ( $ascii_hack_downloads_id and ( $download->{ downloads_id } < $ascii_hack_downloads_id ) )
    {
        $$content_ref =~ s/[^[:ascii:]]/ /g;
    }

    return $content_ref;
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

    my $lines = [ split( /[\n\r]+/, $$content_ref ) ];

    $lines = MediaWords::Crawler::Extractor::preprocess( $lines );

    return $lines;
}

# run MediaWords::Crawler::Extractor against the download content and return a hash in the form of:
# { extracted_html => $html,    # a string with the extracted html
#   extracted_text => $text,    # a string with the extracted html strippped to text
#   download_lines => $lines,   # an array of the lines of original html
#   scores => $scores }         # the scores returned by Mediawords::Crawler::Extractor::score_lines
sub extractor_results_for_download($$)
{
    my ( $db, $download ) = @_;

    my $config           = MediaWords::Util::Config::get_config;
    my $extractor_method = $config->{ mediawords }->{ extractor_method };

    my $extracted_html;
    my $ret;

    #say STDERR "DBI::Downloads::extractor_results_for_download extractor_method $extractor_method";

    if ( $extractor_method eq 'PythonReadability' )
    {
        my $content_ref = fetch_content( $db, $download );

        $ret            = {};
        $extracted_html = MediaWords::Util::ThriftExtractor::get_extracted_html( $$content_ref );
    }
    elsif ( $extractor_method eq 'HeuristicExtractor' )
    {
        my $story = $db->query( "select * from stories where stories_id = ?", $download->{ stories_id } )->hash;

        my $lines = fetch_preprocessed_content_lines( $db, $download );

        # print "PREPROCESSED LINES:\n**\n" . join( "\n", @{ $lines } ) . "\n**\n";

        $ret = extract_preprocessed_lines_for_story( $lines, $story->{ title }, $story->{ description } );

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

    return $ret;
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

sub _do_extraction_from_content_ref($$$)
{
    my ( $content_ref, $title, $description ) = @_;

    my $lines = [ split( /[\n\r]+/, $$content_ref ) ];

    $lines = MediaWords::Crawler::Extractor::preprocess( $lines );

    return extract_preprocessed_lines_for_story( $lines, $title, $description );
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
        my $stores_for_writing = _download_stores_for_writing( $content_ref );
        if ( scalar( @{ $stores_for_writing } ) == 0 )
        {
            die "No download stores configured to write to.\n";
        }
        foreach my $store ( @{ $stores_for_writing } )
        {
            $path = $store->store_content( $db, $download->{ downloads_id }, $content_ref );
        }

        # Now $path points to the last store that was configured
    };
    if ( $@ )
    {
        die "Error while trying to store download ID " . $download->{ downloads_id } . ':' . $@;
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
