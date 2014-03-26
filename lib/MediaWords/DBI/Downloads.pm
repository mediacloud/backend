package MediaWords::DBI::Downloads;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various helper functions for downloads

use strict;

use MediaWords::Crawler::Extractor;
use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::DBI::DownloadTexts;
use MediaWords::StoryVectors;
use MediaWords::DBI::Downloads::Store::AmazonS3;
use MediaWords::DBI::Downloads::Store::DatabaseInline;
use MediaWords::DBI::Downloads::Store::GridFS;
use MediaWords::DBI::Downloads::Store::LocalFile;
use MediaWords::DBI::Downloads::Store::PostgreSQL;
use MediaWords::DBI::Downloads::Store::Remote;
use MediaWords::DBI::Downloads::Store::Tar;
use Carp;
use MediaWords::Util::ExtractorFactory;
use MediaWords::Util::HeuristicExtractor;
use MediaWords::Util::CrfExtractor;

use Data::Dumper;

# Download store instances
my $_amazon_s3_store;
my $_databaseinline_store;
my $_gridfs_store;
my $_localfile_store;
my $_postgresql_store;
my $_remote_store;
my $_tar_store;

# Reference to configuration
my $_config;

# Database inline content length limit
Readonly my $INLINE_CONTENT_LENGTH => 256;

# Constructor
BEGIN
{
    $_amazon_s3_store      = MediaWords::DBI::Downloads::Store::AmazonS3->new();
    $_databaseinline_store = MediaWords::DBI::Downloads::Store::DatabaseInline->new();
    $_gridfs_store         = MediaWords::DBI::Downloads::Store::GridFS->new();
    $_localfile_store      = MediaWords::DBI::Downloads::Store::LocalFile->new();
    $_postgresql_store     = MediaWords::DBI::Downloads::Store::PostgreSQL->new();
    $_remote_store         = MediaWords::DBI::Downloads::Store::Remote->new();
    $_tar_store            = MediaWords::DBI::Downloads::Store::Tar->new();

    # Early sanity check on configuration
    $_config = MediaWords::Util::Config::get_config;
    my $download_storage_locations = $_config->{ mediawords }->{ download_storage_locations };
    if ( scalar( @{ $download_storage_locations } ) == 0 )
    {
        die "No download storage methods are configured.\n";
    }
    foreach my $download_storage_location ( @{ $download_storage_locations } )
    {
        my $location = lc( $download_storage_location );
        unless ( grep { $_ eq $location } ( 'amazon_s3', 'gridfs', 'localfile', 'postgresql', 'tar' ) )
        {
            die "Download storage location '$download_storage_location' is not valid.\n";
        }
    }

}

# Returns arrayref of stores for writing new downloads to
sub _download_stores_for_writing($)
{
    my $content_ref = shift;

    my $stores = [];

    if ( length( $$content_ref ) < $INLINE_CONTENT_LENGTH )
    {

        # Inline
        #say STDERR "Will store inline.";
        push( @{ $stores }, $_databaseinline_store );
    }
    else
    {
        my $download_storage_locations = $_config->{ mediawords }->{ download_storage_locations };
        foreach my $download_storage_location ( @{ $download_storage_locations } )
        {
            my $location = lc( $download_storage_location );

            if ( $location eq 'amazon_s3' )
            {

                #say STDERR "Will store to Amazon S3.";
                push( @{ $stores }, $_amazon_s3_store );

            }
            elsif ( $location eq 'gridfs' )
            {

                #say STDERR "Will store to GridFS.";
                push( @{ $stores }, $_gridfs_store );

            }
            elsif ( $location eq 'localfile' )
            {

                #say STDERR "Will store to local files.";
                push( @{ $stores }, $_localfile_store );

            }
            elsif ( $location eq 'postgresql' )
            {

                #say STDERR "Will store to PostgreSQL.";
                push( @{ $stores }, $_postgresql_store );

            }
            elsif ( $location eq 'tar' )
            {

                #say STDERR "Will store to Tar.";
                push( @{ $stores }, $_tar_store );

            }
            else
            {
                die "Download storage location '$location' is not valid.\n";
            }
        }
    }

    if ( scalar( @{ $stores } ) == 0 )
    {
        die "No download storage locations are configured.\n";
    }

    return $stores;
}

# Returns store for fetching downloads from
sub _download_store_for_reading($)
{
    my $download = shift;

    my $store;

    my $fetch_remote = $_config->{ mediawords }->{ fetch_remote_content } || 'no';
    if ( $fetch_remote eq 'yes' )
    {

        # Remote
        $store = $_remote_store;
    }
    else
    {
        my $path = $download->{ path };
        if ( !$path )
        {
            $store = undef;
        }
        elsif ( $path =~ /^content:(.*)/ )
        {

            # Inline content
            $store = $_databaseinline_store;
        }
        elsif ( $path =~ /^gridfs:(.*)/ )
        {

            # GridFS
            $store = $_gridfs_store;
        }
        elsif ( $path =~ /^postgresql:(.*)/ )
        {

            # PostgreSQL
            $store = $_postgresql_store;
        }
        elsif ( $path =~ /^s3:(.*)/ )
        {

            # Amazon S3
            $store = $_amazon_s3_store;
        }
        elsif ( $download->{ path } =~ /^tar:/ )
        {

            # Tar
            if ( lc( $_config->{ mediawords }->{ read_tar_downloads_from_gridfs } ) eq 'yes' )
            {

                # Force reading Tar downloads from GridFS (after the migration)
                $store = $_gridfs_store;
            }
            else
            {
                $store = $_tar_store;
            }
        }
        else
        {

            # Local file
            if ( lc( $_config->{ mediawords }->{ read_file_downloads_from_gridfs } ) eq 'yes' )
            {

                # Force reading file downloads from GridFS (after the migration)
                $store = $_gridfs_store;
            }
            else
            {
                $store = $_localfile_store;
            }

        }
    }

    return $store;
}

# fetch the content for the given download as a content_ref
sub fetch_content($$)
{
    my ( $db, $download ) = @_;

    carp "fetch_content called with invalid download " unless exists $download->{ downloads_id };

    carp "attempt to fetch content for unsuccessful download $download->{ downloads_id }  / $download->{ state }"
      unless $download->{ state } eq 'success';

    my $store = _download_store_for_reading( $download );
    unless ( defined $store )
    {
        die "No download path or the state is not 'success' for download ID " . $download->{ downloads_id };
    }

    # Fetch content
    if ( my $content_ref = $store->fetch_content( $db, $download ) )
    {

        # horrible hack to fix old content that is not stored in unicode
        my $ascii_hack_downloads_id = $_config->{ mediawords }->{ ascii_hack_downloads_id };
        if ( $ascii_hack_downloads_id && ( $download->{ downloads_id } < $ascii_hack_downloads_id ) )
        {
            $$content_ref =~ s/[^[:ascii:]]/ /g;
        }

        return $content_ref;
    }
    else
    {
        my $ret = '';
        return \$ret;
    }
}

# fetch the content as lines in an array after running through the extractor preprocessor
sub fetch_preprocessed_content_lines($$)
{
    my ( $db, $download ) = @_;

    my $content_ref = fetch_content( $db, $download );

    # print "CONTENT:\n**\n${ $content_ref }\n**\n";

    if ( !$content_ref )
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

    my $story = $db->query( "select * from stories where stories_id = ?", $download->{ stories_id } )->hash;

    my $lines = fetch_preprocessed_content_lines( $db, $download );

    # print "PREPROCESSED LINES:\n**\n" . join( "\n", @{ $lines } ) . "\n**\n";

    return extract_preprocessed_lines_for_story( $lines, $story->{ title }, $story->{ description } );
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

sub _get_included_line_numbers($)
{
    my $scores = shift;

    my @included_lines;
    for ( my $i = 0 ; $i < @{ $scores } ; $i++ )
    {
        if ( $scores->[ $i ]->{ is_story } )
        {
            push @included_lines, $i;
        }
    }

    return \@included_lines;
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
            $path = $store->store_content( $db, $download, $content_ref );
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
        eval { MediaWords::DBI::Downloads::store_content( $db, $download, \$content ) };
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

    $feeds_id || die $db->error;

    my $media_id = $db->query( "SELECT media_id from feeds where feeds_id = ?", $feeds_id )->hash->{ media_id };

    defined( $media_id ) || die "Could not get media id for feeds_id '$feeds_id " . $db->error;

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

sub process_download_for_extractor($$$;$$$)
{
    my ( $db, $download, $process_num, $no_dedup_sentences, $no_vector ) = @_;

    say STDERR "[$process_num] extract: $download->{ downloads_id } $download->{ stories_id } $download->{ url }";
    my $download_text = MediaWords::DBI::DownloadTexts::create_from_download( $db, $download );

    #say STDERR "Got download_text";

    return if ( $no_vector );

    my $remaining_download =
      $db->query( "select downloads_id from downloads " . "where stories_id = ? and extracted = 'f' and type = 'content' ",
        $download->{ stories_id } )->hash;
    if ( !$remaining_download )
    {
        my $story = $db->find_by_id( 'stories', $download->{ stories_id } );

        # my $tags = MediaWords::DBI::Stories::add_default_tags( $db, $story );
        #
        # say STDERR "[$process_num] download: $download->{downloads_id} ($download->{feeds_id}) ";
        # while ( my ( $module, $module_tags ) = each( %{$tags} ) )
        # {
        #     say STDERR "[$process_num] $download->{downloads_id} $module: "
        #       . join( ' ', map { "<$_>" } @{ $module_tags->{tags} } );
        # }

        MediaWords::StoryVectors::update_story_sentence_words_and_language( $db, $story, 0, $no_dedup_sentences );

        # Temporarily commenting this out until we're ready to push it to Amanda.
        # $db->query( " INSERT INTO processed_stories ( stories_id ) VALUES ( ? ) " , $download->{ stories_id }  );
    }
    else
    {
        say STDERR "[$process_num] pending more downloads ...";
    }
}

1;
