package MediaWords::DBI::Downloads;

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

# return a ref to the content associated with the given download, or under if there is none
sub fetch_content_local_file
{
    my ( $download ) = @_;

    my $path = $download->{ path };
    if ( !$download->{ path } || ( $download->{ state } ne "success" ) )
    {
        return undef;
    }

    # note redefine delimitor from '/' to '~'
    $path =~ s~^.*/(content/.*.gz)$~$1~;

    my $config = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };

    $data_dir = "" if ( !$data_dir );
    $path     = "" if ( !$path );
    $path     = "$data_dir/$path";

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

    my $username = MediaWords::Util::Config::get_config->{ mediawords }->{ fetch_remote_content_username };
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
        my $content = $response->content();

        return \$content;
    }
    else
    {
        return \"";
    }
}

# fetch the content for the given download as a content_ref
sub fetch_content
{
    my ( $download ) = @_;

    if ( my $content_ref = fetch_content_local( $download ) )
    {
        return $content_ref;
    }

    my $fetch_remote = MediaWords::Util::Config::get_config->{ mediawords }->{ fetch_remote_content } || 'no';
    if ( $fetch_remote eq 'yes' )
    {
        return fetch_content_remote( $download );
    }
    else
    {
        return \'';
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
sub extract_download
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

sub _contains_block_level_tags
{
    my ( $string ) = @_;

    if (
        $string =~ m{
            (
                <h1> | <h2> | <h3> | <h4> | <h5> | <h6> | <p> | <div> | <dl> | <dt> | <dd> | <ol> | <ul> | <li> | <dir> |
                  <menu> | <address> | <blockquote> | <center> | <div> | <hr> | <ins> | <noscript> | <pre>
            )
        }ix
      )
    {
        return 1;
    }

    if (
        $string =~ m{
            (
                </h1> | </h2> | </h3> | </h4> | </h5> | </h6> | </p> | </div> | </dl> | </dt> | </dd> | </ol> | </ul> |
                  </li> | </dir> | </menu> | </address> | </blockquote> | </center> | </div> | </hr> | </ins> | </noscript> |
                  </pre>
            )
        }ix
      )
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
       (
        <h1>|<h2>|<h3>|<h4>|<h5>|<h6>|
        <p>|
        <div>|
	<dl>|
	<dt>|
	<dd>|
	<ol>|
	<ul>|
	<li>|
	<dir>|
	<menu>|
	<address>|
	<blockquote>|
	<center>|
	<div>|
	<hr>|
	<ins>|
	<noscript>|
	<pre>
      )
      }
      {\n\n$1}gsxi;

    $string =~ s{
       (
        </h1>|</h2>|</h3>|</h4>|</h5>|</h6>|
        </p>|
        </div>|
	</dl>|
	</dt>|
	</dd>|
	</ol>|
	</ul>|
	</li>|
	</dir>|
	</menu>|
	</address>|
	</blockquote>|
	</center>|
	</div>|
	</hr>|
	</ins>|
	</noscript>|
	</pre>
     )
     }
     {$1\n\n}gsxi;

    #say STDERR "_new_lines_around_block_level_tags '$string'";

    #exit;

    #$string = 'sddd';

    return $string;

}

sub get_extracted_html
{
    my ( $lines, $included_lines ) = @_;

    my $is_line_included = { map { $_ => 1 } @{ $included_lines } };

    my $config = MediaWords::Util::Config::get_config;
    my $dont_add_double_new_line_for_block_elements =
      defined( $config->{ mediawords }->{ disable_block_element_sentence_splitting } )
      && ( $config->{ mediawords }->{ disable_block_element_sentence_splitting } eq 'yes' );

    my $extracted_html = '';

    # This variable is used to make sure we don't add unnecessary double newlines
    my $previous_concated_line_was_story = 0;

    for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    {
        if ( $is_line_included->{ $i } )
        {
            my $line_text;

            $previous_concated_line_was_story = 1;

            unless ( $dont_add_double_new_line_for_block_elements )
            {

                $line_text = _new_lines_around_block_level_tags( $lines->[ $i ] );
            }
            else
            {
                $line_text = $lines->[ $i ];
            }

            $extracted_html .= ' ' . $line_text;
        }
        elsif ( _contains_block_level_tags( $lines->[ $i ] ) )
        {

            unless ( $dont_add_double_new_line_for_block_elements )
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
    }

    return $extracted_html;
}

sub _get_extracted_html_for_lines_from_scores
{

    my ( $lines, $scores ) = @_;

    my @included_lines;
    for ( my $i = 0 ; $i < @{ $scores } ; $i++ )
    {
        if ( $scores->[ $i ]->{ is_story } )
        {
            push @included_lines, $i;
        }
    }

    return get_extracted_html( $lines, \@included_lines );

    my $config = MediaWords::Util::Config::get_config;
    my $dont_add_double_new_line_for_block_elements =
      defined( $config->{ mediawords }->{ disable_block_element_sentence_splitting } )
      && ( $config->{ mediawords }->{ disable_block_element_sentence_splitting } eq 'yes' );

    my $extracted_html = '';

    # This variable is used to make sure we don't add unnecessary double newlines
    my $previous_concated_line_was_story = 0;

    for ( my $i = 0 ; $i < @{ $scores } ; $i++ )
    {
        if ( $scores->[ $i ]->{ is_story } )
        {
            my $line_text;

            $previous_concated_line_was_story = 1;

            unless ( $dont_add_double_new_line_for_block_elements )
            {

                $line_text = _new_lines_around_block_level_tags( $lines->[ $i ] );
            }
            else
            {
                $line_text = $lines->[ $i ];
            }

            $extracted_html .= ' ' . $line_text;
        }
        elsif ( _contains_block_level_tags( $lines->[ $i ] ) )
        {

            unless ( $dont_add_double_new_line_for_block_elements )
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
    }

    return $extracted_html;
}

sub extract_preprocessed_lines_for_story
{
    my ( $lines, $story_title, $story_description ) = @_;

    my $scores = MediaWords::Crawler::Extractor::score_lines( $lines, $story_title, $story_description );

    my $extracted_html = _get_extracted_html_for_lines_from_scores( $lines, $scores );

    return {
        extracted_html => $extracted_html,
        extracted_text => html_strip( $extracted_html ),
        download_lines => $lines,
        scores         => $scores
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
