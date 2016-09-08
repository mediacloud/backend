package MediaWords::Crawler::Download::Content;

#
# Handler for 'content' downloads
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
with 'MediaWords::Crawler::DefaultFetcher', 'MediaWords::Crawler::DefaultHandler';

use MediaWords::Crawler::Download::Content::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::Job::ExtractAndVector;
use MediaWords::Util::SQL;

use Readonly;
use URI::Split;

# max number of pages the handler will download for a single story
Readonly my $MAX_PAGES => 10;

# return 1 if medium->{ use_pager } is null or true and 0 otherwise
sub _use_pager
{
    my ( $medium ) = @_;

    return 1 if ( !defined( $medium->{ use_pager } ) || $medium->{ use_pager } );

    return 0;
}

# we keep track of a use_pager field in media to determine whether we should try paging stories within a given media
# souce.  We assume that we don't need to keep trying paging stories if we have tried but failed to find  next pages in
# 100 stories in that media source in a row.
#
# If use_pager is already set, do nothing.  Otherwise, if next_page_url is true, set use_pager to true.  Otherwise, if
# there are less than 100 unpaged_stories, increment unpaged_stories.  If there are at least 100 unpaged_stories, set
# use_pager to false.
sub _set_use_pager
{
    my ( $db, $medium, $next_page_url ) = @_;

    return if ( defined( $medium->{ use_pager } ) );

    if ( $next_page_url )
    {
        $db->query( "update media set use_pager = 't' where media_id = ?", $medium->{ media_id } );
    }
    elsif ( !defined( $medium->{ unpaged_stories } ) )
    {
        $db->query( "update media set unpaged_stories = 1 where media_id = ?", $medium->{ media_id } );
    }
    elsif ( $medium->{ unpaged_stories } < 100 )
    {
        $db->query( "update media set unpaged_stories = unpaged_stories + 1 where media_id = ?", $medium->{ media_id } );
    }
    else
    {
        $db->query( "update media set use_pager = 'f' where media_id = ?", $medium->{ media_id } );
    }
}

# if _use_pager( $medium ) returns true, call MediaWords::Crawler::Download::Content::Pager::get_next_page_url on the download
sub _call_pager
{
    my ( $self, $db, $download ) = @_;
    my $content = \$_[ 3 ];

    my $medium = $db->query( <<END, $download->{ feeds_id } )->hash;
select * from media m where media_id in ( select media_id from feeds where feeds_id = ? );
END

    return unless ( _use_pager( $medium ) );

    if ( $download->{ sequence } > $MAX_PAGES )
    {
        DEBUG "reached max pages ($MAX_PAGES) for url '$download->{ url }'";
        return;
    }

    if ( $db->query( "SELECT * from downloads where parent = ? ", $download->{ downloads_id } )->hash )
    {
        return;
    }

    my $ret;

    my $validate_url = sub { !$db->query( "select 1 from downloads where url = ?", $_[ 0 ] ) };

    my $next_page_url =
      MediaWords::Crawler::Download::Content::Pager::get_next_page_url( $validate_url, $download->{ url }, $content );

    if ( $next_page_url )
    {
        DEBUG "next page: $next_page_url\nprev page: $download->{ url }";

        $ret = $db->create(
            'downloads',
            {
                feeds_id   => $download->{ feeds_id },
                stories_id => $download->{ stories_id },
                parent     => $download->{ downloads_id },
                url        => $next_page_url,
                host       => lc( ( URI::Split::uri_split( $next_page_url ) )[ 1 ] ),
                type       => 'content',
                sequence   => $download->{ sequence } + 1,
                state      => 'pending',
                priority   => $download->{ priority } + 1,
                extracted  => 'f'
            }
        );
    }

    _set_use_pager( $db, $medium, $next_page_url );

    return $ret;
}

sub handle_download($$$$)
{
    my ( $self, $db, $download, $decoded_content ) = @_;

    my $downloads_id = $download->{ downloads_id };
    my $stories_id   = $download->{ stories_id };

    unless ( $downloads_id )
    {
        die "downloads_id is empty";
    }
    unless ( $stories_id )
    {
        die "stories_id is empty";
    }

    DEBUG "Processing content download $downloads_id (story $stories_id)...";

    my $story_ids_to_extract;
    my $next_page = $self->_call_pager( $db, $download, $decoded_content );
    if ( $next_page )
    {
        DEBUG "Skipping download $downloads_id extraction until all pages are available";
        $story_ids_to_extract = [];
    }
    else
    {
        $story_ids_to_extract = [ $download->{ stories_id } ];
    }

    MediaWords::DBI::Downloads::store_content( $db, $download, \$decoded_content );

    DEBUG "Done processing content download $downloads_id (story $stories_id)";

    return $story_ids_to_extract;
}

1;
