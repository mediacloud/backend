package MediaWords::DBI::Downloads;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

=head1 NAME

Mediawords::DBI::Downloads - various helper functions for downloads, including
storing and fetching content

=head1 SYNOPSIS

    my $download = $db->find_by_id( 'downloads', $downloads_id );

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download );

    $$content_ref =~ s/foo/bar/g;

    Mediawords::DBI::Downloads::story_content( $db, $download, $content_ref );

=head1 DESCRIPTION

This module includes various helper function for dealing with downloads.

Most importantly, this module has the store_content and fetch_content
functions, which store and fetch content for a download from the pluggable
content store.

The storage module is configured in mediawords.yml by the
mediawords.download_storage_locations setting.

The three choices are:

* 'postgresql', which stores the content in a separate postgres table and
  optionally database;
* 'amazon_s3', which stores the content in amazon_s3;
* 'databaseinline', which stores the content in the downloads table; downloads
  are no longer stored in `databaseinline', only read from.

The default is 'postgresql', and the production system uses Amazon S3.

This module also includes extract and related functions to handle download
extraction.

=cut

use strict;
use warnings;

use Scalar::Defer;
use Readonly;

use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::Util::ExtractText;
use MediaWords::DB;
use MediaWords::DBI::DownloadTexts;
use MediaWords::DBI::Stories;
use MediaWords::DBI::Stories::ExtractorArguments;
use MediaWords::StoryVectors;
use MediaWords::Util::Paths;
use MediaWords::Util::URL;

# PostgreSQL table name for storing raw downloads
Readonly my $RAW_DOWNLOADS_POSTGRESQL_KVS_TABLE_NAME => 'raw_downloads';

# Min. content length to extract (assuming that it has some HTML in it)
Readonly my $MIN_CONTENT_LENGTH_TO_EXTRACT => 4096;

=head1 FUNCTIONS

=cut

# Inline download store
# (downloads.path is prefixed with "content:", download is stored in downloads.path itself;
# not used for storing downloads anymore, only for reading them)
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
        INFO "Amazon S3 download store is not configured.";
        return undef;
    }

    my $store_package_name = 'MediaWords::KeyValueStore::AmazonS3';
    my $cache_table        = undef;
    if ( $config->{ mediawords }->{ cache_s3_downloads } + 0 )
    {
        $store_package_name = 'MediaWords::KeyValueStore::CachedAmazonS3';
        $cache_table        = 'cache.s3_raw_downloads_cache';
    }

    return $store_package_name->new(
        {
            access_key_id     => $config->{ amazon_s3 }->{ downloads }->{ access_key_id },
            secret_access_key => $config->{ amazon_s3 }->{ downloads }->{ secret_access_key },
            bucket_name       => $config->{ amazon_s3 }->{ downloads }->{ bucket_name },
            directory_name    => $config->{ amazon_s3 }->{ downloads }->{ directory_name },
            cache_table       => $cache_table,
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

    # Raw downloads table
    my $postgresql_store =
      MediaWords::KeyValueStore::PostgreSQL->new( { table => $RAW_DOWNLOADS_POSTGRESQL_KVS_TABLE_NAME } );

    # Add Amazon S3 fallback storage if needed
    if ( $config->{ mediawords }->{ fallback_postgresql_downloads_to_s3 } + 0 )
    {
        my $amazon_s3_store = force $_store_amazon_s3;
        unless ( defined $amazon_s3_store )
        {
            LOGCROAK "'fallback_postgresql_downloads_to_s3' is enabled, but Amazon S3 download storage is not set up.";
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
my $_store_for_writing = lazy
{
    require MediaWords::KeyValueStore::MultipleStores;

    my $config = MediaWords::Util::Config::get_config;

    my @stores_for_writing;

    # Early sanity check on configuration
    my $download_storage_locations = $config->{ mediawords }->{ download_storage_locations };
    if ( scalar( @{ $download_storage_locations } ) == 0 )
    {
        LOGCROAK "No download stores are configured.";
    }

    foreach my $location ( @{ $download_storage_locations } )
    {
        $location = lc( $location );
        my $store;

        if ( $location eq 'databaseinline' )
        {
            LOGCROAK "$location is not valid for storage";

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
            LOGCROAK "Store location '$location' is not valid.";

        }

        unless ( defined $store )
        {
            LOGCROAK "Store for location '$location' is not configured.";
        }

        push( @stores_for_writing, $store );
    }

    return MediaWords::KeyValueStore::MultipleStores->new( { stores_for_writing => \@stores_for_writing, } );
};

# Returns store for writing new downloads to
sub _download_store_for_writing($)
{
    my $content_ref = shift;

    return force $_store_for_writing;
}

# Returns store to try fetching download from
sub _download_store_for_reading($)
{
    my $download = shift;

    my $download_store;

    my $path = $download->{ path };
    unless ( $path )
    {
        LOGCROAK "Download path is not set for download $download->{ downloads_id }";
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
            LOGCROAK "Download location '$location' is unknown for download $download->{ downloads_id }";
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
        LOGCROAK "Download store is undefined for download " . $download->{ downloads_id };
    }

    my $config = MediaWords::Util::Config::get_config;

    # All non-inline downloads have to be fetched from S3?
    if ( $download_store ne force $_store_inline and $config->{ mediawords }->{ read_all_downloads_from_s3 } + 0 )
    {
        $download_store = force $_store_amazon_s3;
    }

    unless ( $download_store )
    {
        LOGCROAK "Download store is not configured for download " . $download->{ downloads_id };
    }

    return $download_store;
}

=head2 fetch_content( $db, $download )

Fetch the content for the given download as a content_ref from the configured content store.

=cut

sub fetch_content($$)
{
    my ( $db, $download ) = @_;

    unless ( exists $download->{ downloads_id } )
    {
        LOGCROAK "fetch_content called with invalid download";
    }

    unless ( download_successful( $download ) )
    {
        LOGCONFESS "attempt to fetch content for unsuccessful download $download->{ downloads_id }  / $download->{ state }";
    }

    my $store = _download_store_for_reading( $download );
    unless ( $store )
    {
        LOGCROAK "No store for reading download " . $download->{ downloads_id };
    }

    # Fetch content
    my $content = $store->fetch_content( $db, $download->{ downloads_id }, $download->{ path } );
    unless ( defined $content )
    {
        LOGCROAK "Unable to fetch content for download " . $download->{ downloads_id } . "; tried store: " . ref( $store );
    }

    my $content_ref = \$content;

    # horrible hack to fix old content that is not stored in unicode
    my $config                  = MediaWords::Util::Config::get_config;
    my $ascii_hack_downloads_id = $config->{ mediawords }->{ ascii_hack_downloads_id };
    if ( $ascii_hack_downloads_id and ( $download->{ downloads_id } < $ascii_hack_downloads_id ) )
    {
        $$content_ref =~ s/[^[:ascii:]]/ /g;
    }

    return $content_ref;
}

=head2 store_content( $db, $download, $content_ref )

Store the download content in the configured content store.

=cut

sub store_content($$$)
{
    my ( $db, $download, $content_ref ) = @_;

    $download = python_deep_copy( $download );

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
            LOGCROAK "No download store to write to.";
        }

        $path = $store->store_content( $db, $download->{ downloads_id }, $$content_ref );
    };
    if ( $@ )
    {
        LOGCROAK "Error while trying to store download ID " . $download->{ downloads_id } . ':' . $@;
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
            error_message = ?
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

# get extractor results from cache
sub _get_cached_extractor_results($$)
{
    my ( $db, $download ) = @_;

    my $r = $db->query( <<SQL, $download->{ downloads_id } )->hash;
select extracted_html, extracted_text from cached_extractor_results where downloads_id = ?
SQL

    TRACE( $r ? "EXTRACTOR CACHE HIT" : "EXTRACTOR CACHE MISS" );

    return $r;
}

# store results in extractor cache and manage size of cache
sub _set_cached_extractor_results($$$)
{
    my ( $db, $download, $results ) = @_;

    my $max_cache_entries = 1_000_000;

    # occasionally delete too old entries in the cache
    if ( rand( $max_cache_entries / 10 ) < 1 )
    {
        $db->query( <<SQL );
delete from cached_extractor_results
    where cached_extractor_results_id in (
            select cached_extractor_results_id from cached_extractor_results
                order by cached_extractor_results_id desc offset $max_cache_entries )
SQL
    }

    my $cache = {
        extracted_html => $results->{ extracted_html },
        extracted_text => $results->{ extracted_text },
        downloads_id   => $download->{ downloads_id }
    };

    $db->create( 'cached_extractor_results', $cache );
}

=head2 extract( $db, $download, $extractor_args )

Run the extractor against the download content and return a hash in the form of:

    { extracted_html => $html,    # a string with the extracted html
      extracted_text => $text }   # a string with the extracted html strippped to text

=cut

sub extract($$;$)
{
    my ( $db, $download, $extractor_args ) = @_;

    $extractor_args //= MediaWords::DBI::Stories::ExtractorArguments->new();

    my $results;
    if ( $extractor_args->use_cache && ( $results = _get_cached_extractor_results( $db, $download ) ) )
    {
        return $results;
    }

    my $content_ref = fetch_content( $db, $download );

    $results = extract_content_ref( $content_ref );

    _set_cached_extractor_results( $db, $download, $results ) if ( $extractor_args->use_cache );

    return $results;
}

# forbes is putting all of its content into a javascript variable, causing our extractor to fall down.
# this function replaces $$content_ref with the html assigned to the javascript variable.
# return true iff the function is able to find and parse the javascript content
sub _parse_out_javascript_content
{
    my ( $content_ref ) = @_;

    if ( $$content_ref =~ s/.*fbs_settings.content[^\}]*body\"\:\"([^"\\]*(\\.[^"\\]*)*)\".*/$1/ms )
    {
        $$content_ref =~ s/\\[rn]/ /g;
        $$content_ref =~ s/\[\w+ [^\]]*\]//g;

        return 1;
    }

    return 0;
}

# call configured extractor on the content_ref
sub _call_extractor_on_html($)
{
    my $content_ref = shift;

    my $extracted_html = MediaWords::Util::ExtractText::extract_article_from_html( $$content_ref );
    my $extracted_text = MediaWords::Util::HTML::html_strip( $extracted_html );

    return {
        'extracted_html' => $extracted_html,
        'extracted_text' => $extracted_text,
    };
}

=head2 extract_content_ref( $content_ref )

Accept a content_ref pointing to an HTML string.  Run the extractor on the HTMl and return the extracted text.

=cut

sub extract_content_ref($)
{
    my $content_ref = shift;

    my $extracted_html;
    my $ret = {};

    # Don't run through expensive extractor if the content is short and has no html
    if ( ( length( $$content_ref ) < $MIN_CONTENT_LENGTH_TO_EXTRACT ) and ( $$content_ref !~ /\<.*\>/ ) )
    {
        TRACE( "Content length is less than $MIN_CONTENT_LENGTH_TO_EXTRACT and has no HTML so skipping extraction" );
        $ret = {
            extracted_html => $$content_ref,
            extracted_text => $$content_ref,
        };
    }
    else
    {
        $ret = _call_extractor_on_html( $content_ref );

        # if we didn't get much text, try looking for content stored in the javascript
        if ( ( length( $ret->{ extracted_text } ) < 256 ) && _parse_out_javascript_content( $content_ref ) )
        {
            my $js_ret = _call_extractor_on_html( $content_ref );

            $ret = $js_ret if ( length( $js_ret->{ extracted_text } ) > length( $ret->{ extracted_text } ) );
        }

    }

    return $ret;
}

=head2 extract_and_create_download_text( $db, $download )

Extract the download and create a download_text from the extracted download.

=cut

sub extract_and_create_download_text($$$)
{
    my ( $db, $download, $extractor_args ) = @_;

    my $downloads_id = $download->{ downloads_id };

    TRACE "Extracting download $downloads_id...";

    my $extract = extract( $db, $download, $extractor_args );
    my $download_text = MediaWords::DBI::DownloadTexts::create( $db, $download, $extract );

    return $download_text;
}

=head2 process_download_for_extractor( $db, $download, $extractor_args )

Extract the download create the resulting download_text entry.  If there are no remaining downloads to be extracted
for the story, call MediaWords::DBI::Stories::process_extracted_story() on the parent story.

=cut

sub process_download_for_extractor($$;$)
{
    my ( $db, $download, $extractor_args ) = @_;

    $extractor_args //= MediaWords::DBI::Stories::ExtractorArguments->new();

    my $stories_id = $download->{ stories_id };

    TRACE "extract: $download->{ downloads_id } $stories_id $download->{ url }";
    my $download_text = MediaWords::DBI::Downloads::extract_and_create_download_text( $db, $download, $extractor_args );

    my $has_remaining_download = $db->query( <<SQL, $stories_id )->hash;
SELECT downloads_id FROM downloads WHERE stories_id = ? AND extracted = 'f' AND type = 'content'
SQL

    if ( $has_remaining_download )
    {
        DEBUG "pending more downloads ...";
    }
    else
    {
        my $story = $db->find_by_id( 'stories', $stories_id );

        MediaWords::DBI::Stories::process_extracted_story( $db, $story, $extractor_args );
    }
}

=head2 download_successful( $download )

Return true if the download was downloaded successfully.
This method is needed because there are cases it which the download was sucessfully downloaded
but had a subsequent processing error. e.g. 'extractor_error' and 'feed_error'

=cut

sub download_successful
{
    my ( $download ) = @_;

    my $state = $download->{ state };

    return ( $state eq 'success' ) || ( $state eq 'feed_error' ) || ( $state eq 'extractor_error' );
}

=head2 get_media_id( $db, $download )

Convenience method to get the media_id for the download.

=cut

sub get_media_id($$)
{
    my ( $db, $download ) = @_;

    return $db->query( "select media_id from feeds where feeds_id = ?", $download->{ feeds_id } )->hash->{ media_id };
}

=head2 get_medium( $db, $download )

Convenience method to get the media source for the given download

=cut

sub get_medium($$)
{
    my ( $db, $download ) = @_;

    return $db->query( <<SQL, $download->{ feeds_id } )->hash;
select m.* from feeds f join media m on ( f.media_id = m.media_id ) where feeds_id = ?
SQL
}

# create a pending download for the story's url
sub create_child_download_for_story
{
    my ( $db, $story, $parent_download ) = @_;

    my $download = {
        feeds_id   => $parent_download->{ feeds_id },
        stories_id => $story->{ stories_id },
        parent     => $parent_download->{ downloads_id },
        url        => $story->{ url },
        host       => MediaWords::Util::URL::get_url_host( $story->{ url } ),
        type       => 'content',
        sequence   => 1,
        state      => 'pending',
        priority   => $parent_download->{ priority },
        extracted  => 'f'
    };

    my ( $content_delay ) = $db->query( "select content_delay from media where media_id = ?", $story->{ media_id } )->flat;
    if ( $content_delay )
    {
        # delay download of content this many hours.  this is useful for sources that are likely to
        # significantly change content in the hours after it is first published.
        my $download_at_timestamp = time() + ( int( $content_delay ) * 60 * 60 );
        $download->{ download_time } = MediaWords::Util::SQL::get_sql_date_from_epoch( $download_at_timestamp );
    }

    $db->create( 'downloads', $download );
}

1;
