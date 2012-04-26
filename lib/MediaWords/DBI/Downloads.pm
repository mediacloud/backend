package MediaWords::DBI::Downloads;
use MediaWords::CommonLibs;

# various helper functions for downloads

use strict;

use Encode;
use File::Path;
use HTTP::Request;
use IO::Uncompress::Gunzip;
use IO::Compress::Gzip;
use LWP::UserAgent;

use Archive::Tar::Indexed;
use MediaWords::Crawler::Extractor;
use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::DBI::DownloadTexts;
use MediaWords::StoryVectors;
use Perl6::Say;
use Data::Dumper;

use constant INLINE_CONTENT_LENGTH => 256;

sub _get_local_file_content_path_from_path
{
    my ( $path ) = @_;

    # note redefine delimitor from '/' to '~'
    $path =~ s~^.*/(content/.*.gz)$~$1~;

    my $config = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };

    $data_dir = "" if ( !$data_dir );
    $path     = "" if ( !$path );
    $path     = "$data_dir/$path";

    return $path;
}

# return a ref to the content associated with the given download, or under if there is none
sub fetch_content_local_file
{
    my ( $download ) = @_;

    my $path = $download->{ path };
    if ( !$download->{ path } || ( $download->{ state } ne "success" ) )
    {
        return undef;
    }

    $path = _get_local_file_content_path_from_path( $path );

    my $content;

    if ( -f $path )
    {
        my $fh;
        if ( !( $fh = IO::Uncompress::Gunzip->new( $path ) ) )
        {
            return undef;
        }

        while ( my $line = $fh->getline )
        {
            $content .= decode( 'utf-8', $line );
        }

        $fh->close;
    }
    else
    {
        $path =~ s/\.gz$/.dl/;

        if ( !open( FILE, $path ) )
        {
            return undef;
        }

        while ( my $line = <FILE> )
        {
            $content .= decode( 'utf-8', $line );
        }
    }

    return \$content;
}

# return a ref to the content associated with the given download, or under if there is none
sub fetch_content_local
{
    my ( $download ) = @_;

    my $path = $download->{ path };
    if ( !$download->{ path } || ( $download->{ state } ne "success" ) )
    {
        return undef;
    }

    if ( $download->{ path } =~ /^content:(.*)/ )
    {
        my $content = $1;
        return \$content;
    }
    elsif ( $download->{ path } !~ /^tar:/ )
    {
        return fetch_content_local_file( $download );
    }

    if ( !( $download->{ path } =~ /tar:(\d+):(\d+):([^:]*):(.*)/ ) )
    {
        warn( "Unable to parse download path: $download->{ path }" );
        return undef;
    }

    my ( $starting_block, $num_blocks, $tar_file, $download_file ) = ( $1, $2, $3, $4 );

    my $config   = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };
    my $tar_path = "$data_dir/content/$tar_file";

    my $content_ref = Archive::Tar::Indexed::read_file( $tar_path, $download_file, $starting_block, $num_blocks );

    my $content;
    if ( !( IO::Uncompress::Gunzip::gunzip $content_ref => \$content ) )
    {
        warn( "Error gunzipping content for download $download->{ downloads_id }: $IO::Uncompress::Gunzip::GunzipError" );
    }

    my $decoded_content = decode( 'utf-8', $content );

    return \$decoded_content;
}

# fetch the content from the production server via http
sub fetch_content_remote
{
    my ( $download ) = @_;

    my $ua = LWP::UserAgent->new;

    if ( !defined( $download->{ downloads_id } ) )
    {
        return \"";
    }

    my $username = MediaWords::Util::Config::get_config->{ mediawords }->{ fetch_remote_content_user };
    my $password = MediaWords::Util::Config::get_config->{ mediawords }->{ fetch_remote_content_password };
    my $url      = MediaWords::Util::Config::get_config->{ mediawords }->{ fetch_remote_content_url };

    if ( !$username || !$password || !$url )
    {
        die( "mediawords:fetch_remote_content_username, _password, and _url must all be set" );
    }

    if ( $url !~ /\/$/ )
    {
        $url = "$url/";
    }

    my $request = HTTP::Request->new( 'GET', $url . $download->{ downloads_id } );
    $request->authorization_basic( $username, $password );

    my $response = $ua->request( $request );

    if ( $response->is_success() )
    {
        my $content = $response->decoded_content();

        return \$content;
    }
    else
    {
        warn( "error fetching remote content: " . $response->as_string );
        return \"";
    }
}

# fetch the content for the given download as a content_ref
sub fetch_content
{
    my ( $download ) = @_;

    my $fetch_remote = MediaWords::Util::Config::get_config->{ mediawords }->{ fetch_remote_content } || 'no';
    if ( $fetch_remote eq 'yes' )
    {
        return fetch_content_remote( $download );
    }
    elsif ( my $content_ref = fetch_content_local( $download ) )
    {
        return $content_ref;
    }
    else
    {
        my $ret = '';
        return \$ret;
    }
}

sub rewrite_downloads_content
{
    my ( $db, $download ) = @_;

    my $fetch_remote = MediaWords::Util::Config::get_config->{ mediawords }->{ fetch_remote_content } || 'no';
    die "CANNOT rewrite mobile content" if ( $fetch_remote eq 'yes' );

    my $download_content_ref = fetch_content( $download );

    my $path = $download->{ path };

    store_content( $db, $download, $download_content_ref );

    my $download_content_ref_new = fetch_content( $download );

    die unless $$download_content_ref eq $$download_content_ref_new;

    die if $path eq $download->{ path };

    my $full_path = _get_local_file_content_path_from_path( $path );

    if ( !( -f $full_path ) )
    {
        $full_path =~ s/\.gz$/.dl/;
    }

    if ( !( -f $full_path ) )
    {
        return if $$download_content_ref eq '';

        say STDERR "file missing: $full_path";
        say STDERR "content is:\n'" . $$download_content_ref . "'";
        warn "File to deleted: '$full_path' does not exist for non-empty content: '$$download_content_ref'"
          unless $$download_content_ref eq '';
    }
    else
    {
        say "Deleting $full_path";
        die "Could not delete $full_path: $! " unless unlink( $full_path );
    }
}

# fetch the content as lines in an array after running through the extractor preprocessor
sub fetch_preprocessed_content_lines
{
    my ( $download ) = @_;

    my $content_ref = fetch_content( $download );

    # print "CONTENT:\n**\n${ $content_ref }\n**\n";

    if ( !$content_ref )
    {
        warn( "unable to find content: " . $download->{ downloads_id } );
        return [];
    }

    my @lines = split( /[\n\r]+/, $$content_ref );

    MediaWords::Crawler::Extractor::preprocess( \@lines );

    return \@lines;
}

# run MediaWords::Crawler::Extractor against the download content and return a hash in the form of:
# { extracted_html => $html,    # a string with the extracted html
#   extracted_text => $text,    # a string with the extracted html strippped to text
#   download_lines => $lines,   # an array of the lines of original html
#   scores => $scores }         # the scores returned by Mediawords::Crawler::Extractor::score_lines
sub extractor_results_for_download
{
    my ( $db, $download ) = @_;

    my $story = $db->query( "select * from stories where stories_id = ?", $download->{ stories_id } )->hash;

    my $lines = fetch_preprocessed_content_lines( $download );

    # print "PREPROCESSED LINES:\n**\n" . join( "\n", @{ $lines } ) . "\n**\n";

    return extract_preprocessed_lines_for_story( $lines, $story->{ title }, $story->{ description } );
}

# if the given line looks like a tagline for another story and is missing an ending period, add a period
#
sub add_period_to_tagline
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

sub _do_extraction_from_content_ref
{
    my ( $content_ref, $title, $description ) = @_;

    my @lines = split( /[\n\r]+/, $$content_ref );

    my $lines = MediaWords::Crawler::Extractor::preprocess( \@lines );

    return extract_preprocessed_lines_for_story( $lines, $title, $description );
}

sub _get_included_line_numbers
{
    my ( $scores ) = @_;

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

sub extract_preprocessed_lines_for_story
{
    my ( $lines, $story_title, $story_description ) = @_;

    my $scores = MediaWords::Crawler::Extractor::score_lines( $lines, $story_title, $story_description );

    my $included_line_numbers = _get_included_line_numbers( $scores );

    #my $extracted_html =  get_extracted_html( $lines, $included_line_numbers );

    return {

        #extracted_html => $extracted_html,
        #extracted_text => html_strip( $extracted_html ),
        included_line_numbers => $included_line_numbers,
        download_lines        => $lines,
        scores                => $scores,
    };
}

# get the parent of this download
sub get_parent
{
    my ( $db, $download ) = @_;

    if ( !$download->{ parent } )
    {
        return undef;
    }

    return $db->query( "select * from downloads where downloads_id = ?", $download->{ parent } )->hash;
}

# get the relative path (to be used within the tarball) to store the given download
# the path for a download is:
# <media_id>/<year>/<month>/<day>/<hour>/<minute>[/<parent download_id>]/<download_id
sub _get_download_path
{
    my ( $db, $download ) = @_;

    my $feed = $db->query( "select * from feeds where feeds_id = ?", $download->{ feeds_id } )->hash;

    my @date = ( $download->{ download_time } =~ /(\d\d\d\d)-(\d\d)-(\d\d).(\d\d):(\d\d):(\d\d)/ );

    my @path = ( sprintf( "%06d", $feed->{ media_id } ), sprintf( "%06d", $feed->{ feeds_id } ), @date );

    for ( my $p = get_parent( $db, $download ) ; $p ; $p = get_parent( $db, $p ) )
    {
        push( @path, $p->{ downloads_id } );
    }

    push( @path, $download->{ downloads_id } . '.gz' );

    return join( '/', @path );
}

# get the name of the tar file for the download
sub _get_tar_file
{
    my ( $db, $download ) = @_;

    my $date = $download->{ download_time };
    $date =~ s/(\d\d\d\d)-(\d\d)-(\d\d).*/$1$2$3/;
    my $file = "mediacloud-content-$date.tar";

    return $file;
}

# store the download content in the file system
sub store_content
{
    my ( $db, $download, $content_ref ) = @_;

    #say STDERR "starting store_content for download $download->{ downloads_id } ";

    #TODO refactor to eliminate common code.

    if ( length( $$content_ref ) < INLINE_CONTENT_LENGTH )
    {
        my $state = 'success';
        my $path  = 'content:' . $$content_ref;
        $db->query( "update downloads set state = ?, path = ? where downloads_id = ?",
            $state, $path, $download->{ downloads_id } );

        $download->{ state } = $state;
        $download->{ path }  = $path;
        return;
    }

    my $download_path = _get_download_path( $db, $download );

    my $config = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };

    my $tar_file = _get_tar_file( $db, $download );
    my $tar_path = "$data_dir/content/$tar_file";

    my $encoded_content = Encode::encode( 'utf-8', $$content_ref );

    my $gzipped_content;

    if ( !( IO::Compress::Gzip::gzip \$encoded_content => \$gzipped_content ) )
    {
        my $error = "Unable to gzip and store content: $IO::Compress::Gzip::GzipError";
        $db->query( "update downloads set state = ?, error_message = ? where downloads_id = ?",
            'error', $error, $download->{ downloads_id } );
    }

    my ( $starting_block, $num_blocks ) = Archive::Tar::Indexed::append_file( $tar_path, \$gzipped_content, $download_path );

    my $tar_id = "tar:$starting_block:$num_blocks:$tar_file:$download_path";

    $db->query( "update downloads set state = ?, path = ? where downloads_id = ?",
        'success', $tar_id, $download->{ downloads_id } );

    $download->{ state } = 'success';
    $download->{ path }  = $tar_id;
}

# convenience method to get the media_id for the download
sub get_media_id
{
    my ( $db, $download ) = @_;

    my $feeds_id = $download->{ feeds_id };

    $feeds_id || die $db->error;

    my $media_id = $db->query( "SELECT media_id from feeds where feeds_id = ?", $feeds_id )->hash->{ media_id };

    defined( $media_id ) || die "Could not get media id for feeds_id '$feeds_id " . $db->error;

    return $media_id;
}

# convenience method to get the media source for the given download
sub get_medium
{
    my ( $db, $download ) = @_;

    my $media_id = get_media_id( $db, $download );

    my $medium = $db->find_by_id( 'media', $media_id );

    return $medium;
}

sub process_download_for_extractor
{
    my ( $db, $download, $process_num ) = @_;

    print STDERR "[$process_num] extract: $download->{ downloads_id } $download->{ stories_id } $download->{ url }\n";
    my $download_text = MediaWords::DBI::DownloadTexts::create_from_download( $db, $download );

    #print STDERR "Got download_text\n";

    my $remaining_download =
      $db->query( "select downloads_id from downloads " . "where stories_id = ? and extracted = 'f' and type = 'content' ",
        $download->{ stories_id } )->hash;
    if ( !$remaining_download )
    {
        my $story = $db->find_by_id( 'stories', $download->{ stories_id } );

        # my $tags = MediaWords::DBI::Stories::add_default_tags( $db, $story );
        #
        # print STDERR "[$process_num] download: $download->{downloads_id} ($download->{feeds_id}) \n";
        # while ( my ( $module, $module_tags ) = each( %{$tags} ) )
        # {
        #     print STDERR "[$process_num] $download->{downloads_id} $module: "
        #       . join( ' ', map { "<$_>" } @{ $module_tags->{tags} } ) . "\n";
        # }

        MediaWords::StoryVectors::update_story_sentence_words( $db, $story );
    }
    else
    {
        print STDERR "[$process_num] pending more downloads ...\n";
    }

}

1;
