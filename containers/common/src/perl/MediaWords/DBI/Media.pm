package MediaWords::DBI::Media;

=head1 NAME

MediaWords::DBI::Media - various helper functions relating to media.

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::IdentifyLanguage;
use MediaWords::DBI::Media::Lookup;
use MediaWords::DBI::Media::Rescrape;
use MediaWords::Util::HTML;
use MediaWords::Util::SQL;
use MediaWords::Util::URL;

use Encode;
use Readonly;
use Regexp::Common qw /URI/;
use Text::Trim;
use XML::FeedPP;

# name of tag_set to use for geo tags
Readonly my $GEOTAG_TAG_SET_NAME => 'mc-geocoder@media.mit.edu';

# minimum proportion requirement for a media source to be tagged with the most tagged geotag
Readonly my $GEOTAG_THRESHOLD => 0.50;

# definition of tag set for assiging a

=head1 FUNCTIONS

=cut

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

=head2 get_medium_domain_counts( $db, $medium )

Return a hash map of domains and counts for the urls of the latest 1000 stories in the given media source.

=cut

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

=head2 find_or_create_media_from_urls( $db, $urls_string, $global_tags_string )

For each url in $urls, either find the medium associated with that url or the medium assocaited with the title from the
given url or, if no medium is found, a newly created medium.  Return the list of all found or created media along with a
list of error messages for the process.

=cut

sub find_or_create_media_from_urls
{
    my ( $dbis, $urls_string, $global_tags_string ) = @_;

    DEBUG "find media from urls";

    my $url_media = _find_media_from_urls( $dbis, $urls_string );

    DEBUG "add missing media";

    _add_missing_media_from_urls( $dbis, $url_media );

    DEBUG "add tags and feeds";

    _add_media_tags_and_feeds_from_strings( $dbis, $url_media, $global_tags_string );

    foreach my $url_medium ( @{ $url_media } )
    {
        my $medium = $url_medium->{ medium };
        MediaWords::DBI::Media::Rescrape::add_feeds_for_feedless_media( $dbis, $medium );
    }

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
        TRACE "'$url_media->[ $i ]->{ url }' eq '$url'";
        if ( MediaWords::Util::URL::urls_are_equal( $url_media->[ $i ]->{ url }, $url ) )
        {
            return $i;
        }
    }

    WARN "Unable to find url '$url' in url_media list";
    return undef;
}

# find the media source by the response.  recurse back along the response to all of the chained redirects
# to see if we can find the media source by any of those urls.
sub _find_medium_by_response
{
    my ( $dbis, $response ) = @_;

    my $r = $response;

    my $medium;
    while ( $r
        && !( $medium = MediaWords::DBI::Media::Lookup::find_medium_by_url( $dbis, decode( 'utf8', $r->request->url() ) ) ) )
    {
        $r = $r->previous;
    }

    return $medium;
}

# fetch the url of all missing media and add those media with the titles from the fetched urls
sub _add_missing_media_from_urls
{
    my ( $dbis, $url_media ) = @_;

    my $fetch_urls = [ map { URI->new( $_->{ url } )->as_string } grep { !( $_->{ medium } ) } @{ $url_media } ];

    $fetch_urls = [ grep { MediaWords::Util::URL::is_http_url( $_ ) } @{ $fetch_urls } ];

    my $ua        = MediaWords::Util::Web::UserAgent->new();
    my $responses = $ua->parallel_get( $fetch_urls );

    for my $response ( @{ $responses } )
    {
        my $original_request = $response->original_request();
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

        my $title =
          MediaWords::Util::HTML::html_title( $response->decoded_content, decode( 'utf8', $response->request->url ), 128 );

        my $medium = _find_medium_by_response( $dbis, $response );

        DEBUG "found medium 1: $medium->{ url }" if ( $medium );

        if ( !$medium )
        {
            if ( $medium = $dbis->query( "select * from media where name = ?", $title )->hash )
            {
                DEBUG "found medium 2: $medium->{ url }";

                $url_media->[ $url_media_index ]->{ message } =
                  "using existing medium with duplicate title '$title' already in database for '$url'";
            }
            else
            {
                say STDERR "Medium to be added: $title $url";
                $medium = $dbis->create( 'media', { name => $title, url => $url } );
                say STDERR "Medium that got added: " . Dumper( $medium );

                MediaWords::DBI::Media::Rescrape::add_to_rescrape_media_queue( $medium );
                say STDERR "Medium after rescraping: " . Dumper( $medium );

                DEBUG "added missing medium: $medium->{ url }";
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

# add a feed with the given url to the medium if the feed does not already exist and
# if the feed validates
sub add_feed_url_to_medium
{
    my ( $db, $medium, $feed_url ) = @_;

    my $feed_exists = $db->query( <<SQL, $medium->{ media_id }, $feed_url )->hash;
select * from feeds where media_id = ? and lower( url ) = lower( ? )
SQL

    return if $feed_exists;

    eval { XML::FeedPP->new( $feed_url ) };
    return if ( $@ );

    $db->create( 'feeds', { media_id => $medium->{ media_id }, name => 'csv imported feed', url => $feed_url } );
}

# given a list of media sources as returned by _find_media_from_urls, add the tags
# and feeds in the tags_string of each medium to that medium
sub _add_media_tags_and_feeds_from_strings
{
    my ( $dbis, $url_media, $global_tags_string ) = @_;

    for my $url_medium ( grep { $_->{ medium } } @{ $url_media } )
    {
        if ( $global_tags_string )
        {
            if ( $url_medium->{ feeds_and_tags } )
            {
                $url_medium->{ feeds_and_tags } .= ";$global_tags_string";
            }
            else
            {
                $url_medium->{ feeds_and_tags } = $global_tags_string;
            }
        }

        if ( defined( $url_medium->{ feeds_and_tags } ) )
        {
            for my $item ( split( /;/, $url_medium->{ feeds_and_tags } ) )
            {
                if ( $item =~ /^https?\:/i )
                {
                    DEBUG "add feed: $item";
                    add_feed_url_to_medium( $dbis, $url_medium->{ medium }, $item );
                }
                else
                {
                    DEBUG "add tag: $item";
                    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $dbis, lc( $item ) );
                    next unless ( $tag );

                    my $media_id = $url_medium->{ medium }->{ media_id };

                    $dbis->find_or_create( 'media_tags_map', { tags_id => $tag->{ tags_id }, media_id => $media_id } );
                }
            }
        }
    }
}

# given a newline separated list of media urls, return a list of hashes in the form of
# { medium => $medium_hash, url => $url, feeds_and_tags => $feeds_and_tags, message => $error_message }
# the $medium_hash is the existing media source with the given url, or undef if no existing media source is found.
# the feeds_and_tags is everything after a space on a line, to be used to add feeds and tags to the media source later.
sub _find_media_from_urls
{
    my ( $dbis, $urls_string ) = @_;

    my $url_media = [];

    my $urls = [ split( "\n", $urls_string ) ];

    for my $tagged_url ( @{ $urls } )
    {
        my $medium;

        trim( $tagged_url );

        next unless $tagged_url;

        my ( $url, $feeds_and_tags ) = ( $tagged_url =~ /^\r*\s*([^\s]*)(?:\s+(.*))?/ );

        if ( $url !~ m~^[a-z]+://~ )
        {
            $url = "http://$url";
        }

        $medium->{ url }            = $url;
        $medium->{ feeds_and_tags } = $feeds_and_tags;

        if ( $url !~ /$RE{URI}/ )
        {
            $medium->{ message } = "'$url' is not a valid url";
        }

        $medium->{ medium } = MediaWords::DBI::Media::Lookup::find_medium_by_url( $dbis, $url );

        push( @{ $url_media }, $medium );
    }

    return $url_media;
}

=head2 get_media_type_tags( $db, $topics_id )

Get all of the media_type: tags. append the tags from the topics.media_type_tags_sets_id if $topics_id is
specified.

=cut

sub get_media_type_tags
{
    my ( $db, $topics_id ) = @_;

    my $media_types = $db->query( <<END )->hashes;
select t.*
    from
        tags t join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id )
    where
        ts.name = 'media_type'
    order by t.label = 'Not Typed' desc, t.label = 'Other', t.label
END

    if ( $topics_id )
    {
        my $topic_media_types = $db->query( <<END, $topics_id )->hashes;
select t.*
    from
        tags t
        join topics c on ( t.tag_sets_id = c.media_type_tag_sets_id )
    where
        c.topics_id = ? and
        t.label <> 'Not Typed'
    order by t.label
END

        push( @{ $media_types }, @{ $topic_media_types } );
    }

    return $media_types;
}

=head2 update_media_type( $db, $medium, $media_type_tags_id )

Update the media type tag for the given medium by deleting any existing tags in the same tag set as the new tag and
inserting the new media_tags_map row if it does not already exist.

=cut

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

=head2 medium_is_ready_for_analysis( $db, $medium )

Return true if the media sources has enough stories or is old enough that we are ready to analyze it for
primary language, geo tagging, etc.

use the following rules to determine if the media source is ready:

* return true if the medium has an active feed and more than 100 stories;

* return false otherwise

=cut

sub medium_is_ready_for_analysis($$)
{
    my ( $db, $medium ) = @_;

    my $media_id = $medium->{ media_id };

    my $active_feed = $db->query( "select 1 from feeds where active = 't' and media_id = \$1", $media_id )->hash;

    return 0 unless ( $active_feed );

    my $first_story = $db->query( <<SQL, $media_id )->hash;
select * from stories where media_id = \$1 limit 1
SQL

    return 0 unless ( $first_story );

    my $story_101 = $db->query( <<SQL, $media_id )->hash;
    select * from stories where media_id = \$1 offset 101 limit 1
SQL

    return $story_101 ? 1 : 0;
}

1;
