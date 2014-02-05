use MediaWords::StoryVectors;

use Data::Dumper;
use DateTime;
use Encode;
use HTTP::Cookies;
use HTTP::Request::Common;
use LWP::UserAgent;
use Text::CSV_XS;

use constant ARCHIVE_ORG_USERNAME  => 'hroberts@cyber.law.harvard.edu';
use constant ARCHIVE_ORG_PASSWORD  => 'dw7sjQmwE7';
use constant ARCHIVE_ORG_LOGIN_URL => 'http://archive.org/account/login.php';

my $_archive_org_cookie_jar;

# login to archive.org and return the cookies object with the auth
sub get_archive_org_login_cookies
{
    return $_archive_org_cookie_jar if ( $_archive_org_cookie_jar );

    my $cookies = HTTP::Cookies->new( autosave => 0 );

    my $ua = LWP::UserAgent->new;

    $ua->cookie_jar( $cookies );

    $ua->get( ARCHIVE_ORG_LOGIN_URL );

#username=hroberts%40cyber.law.harvard.edu&password=foobar&remember=CHECKED&referer=http%3A%2F%2Farchive.org%2F&submit=Log+in

    my $request = POST ARCHIVE_ORG_LOGIN_URL,
      [
        username => ARCHIVE_ORG_USERNAME,
        password => ARCHIVE_ORG_PASSWORD,
        submit   => 'Log in',
        referer  => 'http://archive.org/',
        remember => 'CHECKED'
      ];

    push( @{ $ua->requests_redirectable }, 'POST' );

    my $response = $ua->request( $request );

    die( "Unable to login to archive.org: " . $response->as_string ) unless ( $response->is_success );

    $_archive_org_cookie_jar = $cookies;

    return $cookies;
}

# fetch url from archive.org, logging in or using auth cookie
sub fetch_url_from_archive_org
{
    my ( $url ) = @_;

    my $cookie_jar = get_archive_org_login_cookies();

    my $ua = LWP::UserAgent->new;

    $ua->cookie_jar( $cookie_jar );

    my $response = $ua->get( $url );

    if ( !$response->is_success )
    {
        print STDERR "error fetching '$url': " . $response->status_line . "\n";
        return '';
    }

    return $response->decoded_content;
}

# find existing or create new medium and feed based on the show info
sub find_or_create_medium_and_feed
{
    my ( $db, $show ) = @_;

    my $medium_name = $show->{ subject };
    $medium_name =~ s/^([^;]*).*/$1/;

    my $medium_url = $show->{ identifier };
    $medium_url =~ s/^.*_20\d+_\d+_(.*)/$1/;

    $medium_url = "urn://archive.org/$medium_url";

    my $medium = $db->query( "select * from media where name = ? and url = ?", $medium_name, $medium_url )->hash;

    if ( $medium )
    {
        my $feed = $db->query( "select * from feeds where media_id = ?", $medium->{ media_id } )->hash;

        die( "Unable to find feed for medium $medium->{ media_id }" ) unless ( $feed );

        return ( $medium, $feed );
    }

    print STDERR "create medium: $medium_name / $medium_url\n";

    $medium = $db->create(
        'media',
        {
            name          => $medium_name,
            url           => $medium_url,
            moderated     => 't',
            feeds_added   => 't',
            full_text_rss => 'f'
        }
    );

    my $feed = $db->create(
        'feeds',
        {
            media_id => $medium->{ media_id },
            name     => $medium_name,
            url      => $medium_url
        }
    );

    return ( $medium, $feed );
}

# parse the csv from archive.org to get the metadata about each show.
# returns a list of shows in this format:
#  {
#       'subject' => 'KRON 4 News at 4;Television Program',
#       'date' => '2010-11-13',
#       'details' => 'http://www.archive.org/details/KRON_20101113_000000_KRON_4_News_at_4',
#       'description' => 'News  News/Business. New. (CC) (Stereo)',
#       'size' => '958084',
#       'identifier' => 'KRON_20101113_000000_KRON_4_News_at_4',
#       'format' => 'Animated GIF;Closed Caption Text;MP3;MPEG2;Metadata;SubRip;Thumbnail;Video Index;ZIP;h.264',
#       'title' => 'KRON 4 News at 4 : KRON : November 12, 2010 4:00pm-4:30pm PST'
# }
sub get_shows_from_csv
{
    my ( $file ) = @_;

    my $csv = Text::CSV_XS->new( { binary => 1, sep_char => "\t" } )
      || die "error using CSV_XS: " . Text::CSV_XS->error_diag();

    open my $fh, "<:encoding(utf8)", $file || die "Unable to open file $file: $!\n";

    $csv->column_names( $csv->getline( $fh ) );

    my $shows = [];
    while ( my $show = $csv->getline_hr( $fh ) )
    {
        push( @{ $shows }, $show );
    }

    return $shows;
}

# import show by adding a story to the db if it doesn't already exist.  also
# create medium and feed if necessary
sub find_or_create_story
{
    my ( $db, $medium, $feed, $show ) = @_;

    my $story_url   = "urn://archive.org/$show->{ identifier }";
    my $story_date  = $show->{ date };
    my $story_title = $show->{ title };

    my $story =
      $db->query( "select * from stories where media_id = ? and guid = ?", $medium->{ media_id }, $story_url )->hash;

    return $story if ( $story );

    print STDERR "create story $story_url / $story_title\n";

    my $story = $db->create(
        'stories',
        {
            media_id     => $medium->{ media_id },
            url          => $story_url,
            guid         => $story_url,
            title        => $story_title,
            publish_date => $story_date,
            collect_date => DateTime->now->datetime
        }
    );

    $db->query(
        "insert into feeds_stories_map ( feeds_id, stories_id ) values ( ?, ? )",
        $feed->{ feeds_id },
        $story->{ stories_id }
    );

    return $story;
}

sub fetch_cc_from_archive_org
{
    my ( $show ) = @_;

    my $id = $show->{ identifier };

    my $story_content = '';

    for my $i ( 1, 2, 3 )
    {
        my $cc_url = "http://archive.org/download/$id/$id.cc${ i }.txt";

        print STDERR "fetch $cc_url\n";

        my $cc_content = fetch_url_from_archive_org( $cc_url ) || next;

        if ( length( $cc_content ) > length( $story_content ) )
        {
            $story_content = $cc_content;
        }
    }

    if ( !$story_content )
    {
        print STDERR "Unable to find valid cc content for $id\n";
    }

    return $story_content;
}

# find an existing download for the story or else fetch the cc for the show, add a download,
# and store the fetched cc under the download
sub find_or_fetch_and_create_download
{
    my ( $db, $story, $feed, $show ) = @_;

    my $download = $db->query( "select * from downloads where stories_id = ?", $story->{ stories_id } )->hash;

    return $download if ( $download );

    my $story_content = fetch_cc_from_archive_org( $show ) || return undef;

    $download = $db->create(
        'downloads',
        {
            feeds_id      => $feed->{ feeds_id },
            stories_id    => $story->{ stories_id },
            url           => $story->{ url },
            host          => 'archive.org',
            download_time => DateTime->now->datetime,
            type          => 'content',
            state         => 'pending',
            priority      => 0,
            sequence      => 0,
            extracted     => 't'
        }
    );

    MediaWords::DBI::Downloads::store_content( $db, $download, \$story_content );

    return $download;
}

# if there's no download text for the download, create it by cleaning up the cc content for the download
sub find_or_create_download_text
{
    my ( $db, $download ) = @_;

    my $download_text =
      $db->query( "select * from download_texts where downloads_id = ?", $download->{ downloads_id } )->hash;

    return $download_text if ( $download_text );

    print STDERR "create download text\n";

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $download );

    my $content = ${ $content_ref };

    print STDERR "content length: " . length( $content ) . "\n";

    $content =~ s/\[\d+:\d+:\d+;\d+\]//g;

    my $encoded_content = encode( 'utf8', $content );

    $download_text = $db->create(
        'download_texts',
        {
            downloads_id         => $download->{ downloads_id },
            download_text        => $encoded_content,
            download_text_length => length( $encoded_content ),
        }
    );

    return $download_text;
}

# import show by adding a story with download and download_text to the database
sub import_show
{
    my ( $db, $show ) = @_;

    print STDERR "import show: $show->{ identifier }\n";

    my ( $medium, $feed ) = find_or_create_medium_and_feed( $db, $show );

    my $story = find_or_create_story( $db, $medium, $feed, $show );

    my $download = find_or_fetch_and_create_download( $db, $story, $feed, $show ) || return;

    my $download_text = find_or_create_download_text( $db, $download );

    #MediaWords::StoryVectors::update_story_sentence_words_and_language( $db, $story );

    print STDERR
"import show complete: s $story->{ stories_id } / d $download->{ downloads_id } / dt $download_text->{ download_texts_id }\n";
}

sub main
{
    my ( $csv ) = @ARGV;

    die( "usage: $0 <csv file>" ) unless $csv;

    my $db = MediaWords::DB::connect_to_db;

    my $shows = get_shows_from_csv( $csv );

    map { import_show( $db, $_ ); } @{ $shows };
}

main();
