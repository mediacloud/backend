package MediaWords::DBI::Media;

use strict;
use warnings;

use Modern::Perl "2013";

use Encode;
use Regexp::Common qw /URI/;
use Text::Trim;

use MediaWords::CommonLibs;
use MediaWords::DBI::Media::Lookup;
use MediaWords::GearmanFunction;
use MediaWords::GearmanFunction::RescrapeMedia;
use MediaWords::Util::HTML;
use MediaWords::Util::URL;

# parse the domain from the url of each story.  return the list of domains
sub _get_domains_from_story_urls
{
    my ( $stories ) = @_;

    my $domains = [];

    for my $story ( @{ $stories } )
    {
        my $url = $story->{ url };

        next unless ( $url =~ m~https?://([^/]*)~ );

        my $host = $1;

        my $name_parts = [ split( /\./, $host ) ];

        my $n = @{ $name_parts } - 1;

        my $domain;
        if ( $host =~ /\.co.[a-z]+$/ )
        {
            $domain = join( ".", ( $name_parts->[ $n - 2 ], $name_parts->[ $n - 1 ], $name_parts->[ $n ] ) );
        }
        else
        {
            $domain = join( ".", $name_parts->[ $n - 1 ], $name_parts->[ $n ] );
        }

        push( @{ $domains }, lc( $domain ) );
    }

    return $domains;
}

# return a hash map of domains and counts for the urls of the latest 1000 stories in the given media source
sub get_medium_domain_counts
{
    my ( $db, $medium ) = @_;

    my $media_id = $medium->{ media_id } + 0;

    my $stories = $db->query( <<END )->hashes;
select url from stories where media_id = $media_id order by date_trunc( 'day', publish_date ) limit 1000
END

    my $domains = _get_domains_from_story_urls( $stories );

    my $domain_map = {};
    map { $domain_map->{ $_ }++ } @{ $domains };

    return $domain_map;
}

# for each medium in $media, enqueue an RescrapeMedia job for any medium
# that is lacking feeds
sub _add_feeds_for_feedless_media
{
    my ( $db, $media ) = @_;

    for my $medium ( @{ $media } )
    {
        my $feeds = $db->query( <<END, $medium->{ media_id } )->hashes;
select * from feeds where media_id = ? and feed_status = 'active' and feed_type = 'syndicated'
END

        enqueue_rescrape_media( $medium ) unless ( @{ $feeds } );
    }
}

# for each url in $urls, either find the medium associated with that
# url or the medium assocaited with the title from the given url or,
# if no medium is found, a newly created medium.  Return the list of
# all found or created media along with a list of error messages for the process.
sub find_or_create_media_from_urls
{
    my ( $dbis, $urls_string, $tags_string ) = @_;

    my $url_media = _find_media_from_urls( $dbis, $urls_string );

    _add_missing_media_from_urls( $dbis, $url_media );

    _add_media_tags_from_strings( $dbis, $url_media, $tags_string );

    _add_feeds_for_feedless_media( $dbis, [ map { $_->{ medium } } @{ $url_media } ] );

    return [ grep { $_ } map { $_->{ message } } @{ $url_media } ];
}

# given a set of url media (as returned by _find_media_from_urls) and a url
# return the index of the media source in the list whose url is the same as the url fetched the response.
# note that the url should be the original url and not any redirected urls (such as might be stored in
# response->request->url).
sub _get_url_medium_index_from_url
{
    my ( $url_media, $url ) = @_;

    for ( my $i = 0 ; $i < @{ $url_media } ; $i++ )
    {

        #print STDERR "'$url_media->[ $i ]->{ url }' eq '$url'\n";
        if ( URI->new( $url_media->[ $i ]->{ url } ) eq URI->new( $url ) )
        {
            return $i;
        }
    }

    warn( "Unable to find url '" . $url . "' in url_media list" );
    return undef;
}

# given an lwp response, grab the title of the media source as the <title> content or missing that the response url
sub _get_medium_title_from_response
{
    my ( $response ) = @_;

    my $content = $response->decoded_content;

    my ( $title ) = ( $content =~ /<title>(.*?)<\/title>/is );
    $title = html_strip( $title );
    $title = trim( $title );
    $title ||= trim( decode( 'utf8', $response->request->url ) );
    $title =~ s/\s+/ /g;

    $title =~ s/^\W*home\W*//i;

    $title = substr( $title, 0, 128 );

    return $title;
}

# find the media source by the response.  recurse back along the response to all of the chained redirects
# to see if we can find the media source by any of those urls.
sub _find_medium_by_response
{
    my ( $dbis, $response ) = @_;

    my $r = $response;

    my $medium;
    while ( $r
        && !( $medium = MediaWords::DBI::Media::Lookup::find_medium_by_url( $dbis, decode( 'utf8', $r->request->url ) ) ) )
    {
        $r = $r->previous;
    }

    return $medium;
}

# fetch the url of all missing media and add those media with the titles from the fetched urls
sub _add_missing_media_from_urls
{
    my ( $dbis, $url_media ) = @_;

    my $fetch_urls = [ map { URI->new( $_->{ url } ) } grep { !( $_->{ medium } ) } @{ $url_media } ];

    my $responses = MediaWords::Util::Web::ParallelGet( $fetch_urls );

    for my $response ( @{ $responses } )
    {
        my $original_request = MediaWords::Util::Web->get_original_request( $response );
        my $url              = $original_request->url;

        my $url_media_index = _get_url_medium_index_from_url( $url_media, $url );
        if ( !defined( $url_media_index ) )
        {
            next;
        }

        if ( !$response->is_success )
        {
            $url_media->[ $url_media_index ]->{ message } = "Unable to fetch medium url '$url': " . $response->status_line;
            next;
        }

        my $title = _get_medium_title_from_response( $response ) || $url;

        my $medium = _find_medium_by_response( $dbis, $response );

        if ( !$medium )
        {
            if ( $medium = $dbis->query( "select * from media where name = ?", encode( 'UTF-8', $title ) )->hash )
            {
                $url_media->[ $url_media_index ]->{ message } =
                  "using existing medium with duplicate title '$title' already in database for '$url'";
            }
            else
            {
                $medium = $dbis->create(
                    'media',
                    {
                        name      => encode( 'UTF-8', $title ),
                        url       => encode( 'UTF-8', $url ),
                        moderated => 'f',
                    }
                );
                enqueue_rescrape_media( $medium );
            }
        }

        $url_media->[ $url_media_index ]->{ medium } = $medium;
    }

    # add error message for any url_media that were not found
    # if there's just one missing
    for my $url_medium ( @{ $url_media } )
    {
        if ( !$url_medium->{ medium } )
        {
            $url_medium->{ message } ||= "Unable to find medium for url '$url_medium->{ url }'";
        }
    }
}

# given a list of media sources as returned by _find_media_from_urls, add the tags
# in the tags_string of each medium to that medium
sub _add_media_tags_from_strings
{
    my ( $dbis, $url_media, $global_tags_string ) = @_;

    for my $url_medium ( grep { $_->{ medium } } @{ $url_media } )
    {
        if ( $global_tags_string )
        {
            if ( $url_medium->{ tags_string } )
            {
                $url_medium->{ tags_string } .= ";$global_tags_string";
            }
            else
            {
                $url_medium->{ tags_string } = $global_tags_string;
            }
        }

        if ( defined( $url_medium->{ tags_string } ) )
        {
            for my $tag_string ( split( /;/, $url_medium->{ tags_string } ) )
            {
                my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $dbis, lc( $tag_string ) );
                return unless ( $tag );

                my $media_id = $url_medium->{ medium }->{ media_id };

                $dbis->find_or_create( 'media_tags_map', { tags_id => $tag->{ tags_id }, media_id => $media_id } );
            }
        }
    }
}

# given a newline separated list of media urls, return a list of hashes in the form of
# { medium => $medium_hash, url => $url, tags_string => $tags_string, message => $error_message }
# the $medium_hash is the existing media source with the given url, or undef if no existing media source is found.
# the tags_string is everything after a space on a line, to be used to add tags to the media source later.
sub _find_media_from_urls
{
    my ( $dbis, $urls_string ) = @_;

    my $url_media = [];

    my $urls = [ split( "\n", $urls_string ) ];

    for my $tagged_url ( @{ $urls } )
    {
        my $medium;

        trim( $tagged_url );

        my ( $url, $tags_string ) = ( $tagged_url =~ /^\r*\s*([^\s]*)(?:\s+(.*))?/ );

        if ( $url !~ m~^[a-z]+://~ )
        {
            $url = "http://$url";
        }

        $medium->{ url }         = $url;
        $medium->{ tags_string } = $tags_string;

        if ( $url !~ /$RE{URI}/ )
        {
            $medium->{ message } = "'$url' is not a valid url";
        }

        $medium->{ medium } = MediaWords::DBI::Media::Lookup::find_medium_by_url( $dbis, $url );

        push( @{ $url_media }, $medium );
    }

    return $url_media;
}

# get the domain from the medium url
sub get_medium_domain
{
    my ( $medium ) = @_;

    return MediaWords::Util::URL::get_url_domain( $medium->{ url } );
}

# add default feeds for a single medium
sub enqueue_rescrape_media($)
{
    my ( $medium ) = @_;

    return MediaWords::GearmanFunction::RescrapeMedia->enqueue_on_gearman( { media_id => $medium->{ media_id } } );
}

# (re-)enqueue RescrapeMedia jobs for all unmoderated media
# ("RescrapeMedia" Gearman function is "unique", so Gearman will skip media
# IDs that are already enqueued)
sub enqueue_rescrape_media_for_unmoderated_media($)
{
    my ( $db ) = @_;

    my $media = $db->query( "select * from media where media_has_feeds(media_id) = 'f'" )->hashes;

    map { enqueue_rescrape_media( $_ ) } @{ $media };

    return 1;
}

# get all of the media_type: tags. append the tags from the controversies.media_type_tags_sets_id
# if $controversies_id is specified.
sub get_media_type_tags
{
    my ( $db, $controversies_id ) = @_;

    my $media_types = $db->query( <<END )->hashes;
select t.*
    from 
        tags t join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where
        ts.name = 'media_type'
    order by t.label = 'Not Typed' desc, t.label = 'Other', t.label
END

    if ( $controversies_id )
    {
        my $controversy_media_types = $db->query( <<END, $controversies_id )->hashes;
select t.*
    from 
        tags t 
        join controversies c on ( t.tag_sets_id = c.media_type_tag_sets_id )
    where
        c.controversies_id = ? and
        t.label <> 'Not Typed'
    order by t.label
END

        push( @{ $media_types }, @{ $controversy_media_types } );
    }

    return $media_types;
}

# update the media type tag for the given medium by deleting any existing tags
# in the same tag set as the new tag and inserting the new media_tags_map row
# if it does not already exist.
sub update_media_type
{
    my ( $db, $medium, $media_type_tags_id ) = @_;

    # delete existing tags in the media_type_tags_id tag set that are not the new tag
    $db->query( <<END, $medium->{ media_id }, $media_type_tags_id );
delete from media_tags_map mtm
    using 
        tags t
    where
        mtm.media_id = \$1 and
        mtm.tags_id <> \$2 and
        mtm.tags_id = t.tags_id and
        t.tag_sets_id in (
            select tag_sets_id from tags new_tag where new_tag.tags_id = \$2 )
END

    return unless ( $media_type_tags_id );

    # only insert the tag if it does not already exist
    $db->query( <<END, $medium->{ media_id }, $media_type_tags_id );
insert into media_tags_map ( media_id, tags_id )
    select \$1, \$2 where not exists ( 
        select 1 from media_tags_map where media_id = \$1 and tags_id = \$2
    )
END
}

1;
