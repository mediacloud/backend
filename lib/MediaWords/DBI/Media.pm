package MediaWords::DBI::Media;

=head1 NAME

MediaWords::DBI::Media - various helper functions relating to media.

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

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

# definition of tag set for media primary language
Readonly my $PRIMARY_LANGUAGE_TAG_SET_NAME        => 'primary_language';
Readonly my $PRIMARY_LANGUAGE_TAG_SET_LABEL       => 'Primary Language';
Readonly my $PRIMARY_LANGUAGE_TAG_SET_DESCRIPTION => <<END;
Tags in this set indicate that the given media source has a majority of stories written in the given language.
END

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
        if ( URI->new( $url_media->[ $i ]->{ url } ) eq URI->new( $url ) )
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

    my $fetch_urls = [ map { URI->new( $_->{ url } ) } grep { !( $_->{ medium } ) } @{ $url_media } ];

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
                $medium = $dbis->create( 'media', { name => $title, url => $url, moderated => 'f' } );
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

# detect the primary language of the media source, as described in set_primary_language below
sub _detect_primary_language($$)
{
    my ( $db, $medium ) = @_;

    my $media_id = $medium->{ media_id };

    TRACE( "detect primary language for $medium->{ name } [$media_id] start" );

    my $active_feed = $db->query( "select 1 from feeds where feed_status = 'active' and media_id = \$1", $media_id )->hash;

    return unless ( $active_feed );

    TRACE( "detect primary language for $medium->{ name } [$media_id] found active feed" );

    my $first_story = $db->query( <<SQL, $media_id )->hash;
select * from stories where media_id = \$1 limit 1
SQL

    return unless ( $first_story );

    TRACE( "detect primary language for $medium->{ name } [$media_id] found at least one story" );

    my $story_101 = $db->query( <<SQL, $media_id )->hash;
    select * from stories where media_id = \$1 offset 101 limit 1
SQL

    if ( !$story_101 )
    {
        my $last_story = $db->query( <<SQL, $media_id )->hash;
select * from stories where media_id = \$1 order by collect_date desc limit 1
SQL

        my $story_epoch = MediaWords::Util::SQL::get_epoch_from_sql_date( $last_story->{ collect_date } );

        TRACE(
"detect primary language for $medium->{ name } [$media_id] latest date $last_story->{ collect_date } (epoch $story_epoch)"
        );
        return if ( ( time() - $story_epoch ) < ( 86400 * 30 ) );
    }

    DEBUG( "detect primary language for $medium->{ name } [$media_id] ..." );

    my $language_counts = $db->query( <<SQL, $media_id )->hashes;
select count(*) count, language
    from stories
    where
        media_id = \$1 and
        language is not null
    group by language
    order by count(*) desc
SQL

    my $first_language = $language_counts->[ 0 ];

    my $total_count = 0;
    map { $total_count += $_->{ count } } @{ $language_counts };

    my $primary_language = ( ( $first_language->{ count } / $total_count ) ) > 0.5 ? $first_language->{ language } : 'none';

    DEBUG( "detect primary language for $medium->{ name } [$media_id] update to $primary_language" );

    return $primary_language;

}

=head2 get_primary_language_tag_set( $db )

Return the tag_set containing the primary language tags.

=cut

sub get_primary_language_tag_set($)
{
    my ( $db ) = @_;

    my $tag_set = $db->find_or_create(
        'tag_sets',
        {
            name        => $PRIMARY_LANGUAGE_TAG_SET_NAME,
            label       => $PRIMARY_LANGUAGE_TAG_SET_LABEL,
            description => $PRIMARY_LANGUAGE_TAG_SET_DESCRIPTION,
        }
    );

    return $tag_set;
}

=head2 return the tag for the given language code( $db, $language_code )

Given a language code, returm the primary language tag corresponding to that language.

=cut

sub get_primary_language_tag($$)
{
    my ( $db, $primary_language ) = @_;

    my $tag_set = get_primary_language_tag_set( $db );

    my $tag = $db->query( <<SQL, $primary_language, $tag_set->{ tag_sets_id } )->hash;
select t.*
    from tags t
    where
        t.tag = \$1 and
        t.tag_sets_id = \$2
SQL

    if ( !$tag )
    {
        my $label = MediaWords::Util::IdentifyLanguage::language_name_for_code( $primary_language );
        $label ||= $primary_language;

        my $description = "Media sources for which the primary language is $label";
        $tag = $db->create(
            'tags',
            {
                tag         => $primary_language,
                label       => $label,
                description => $description,
                tag_sets_id => $tag_set->{ tag_sets_id }
            }
        );
    }

    return $tag;
}

=head2 get_primary_language_tag( $db, $medium )

Return the primary language tag associated with the given media source, or undef if none exists.

=cut

sub get_primary_language_tag_for_medium($$)
{
    my ( $db, $medium ) = @_;

    my $tag_set = get_primary_language_tag_set( $db );

    my $tag = $db->query( <<SQL, $medium->{ media_id }, $tag_set->{ tag_sets_id } )->hash;
select t.*
    from tags t
        join media_tags_map mtm using ( tags_id )
    where
        mtm.media_id = \$1 and
        t.tag_sets_id = \$2
SQL

    return $tag;
}

=head2 set_primary_language( $db, $medium )

Assign a $PRIMAY_LANGuAGE_TAG_SET_NAME: tag to the media source as the language of the greatest number of stories in the
source as long as that language is more than 50% of the stories in the media source.  Delete any existing associations
to tags in the $PRIMAY_LANGuAGE_TAG_SET_NAME tag_set if they do not match the newly detected tag.

Use the following rules to assign the primary language tag:

* assign no tag if the medium has no active feeds or no stories;

* assign no tag if there are less than 100 stories in the medium and the greatest last_new_story_time of the
medium's feeds is within a month;

* assign the majority story language if there are more than 100 stories in the medium;

* assign the majority story language if there are less than 100 stories in the medium but the greatest
last_new_story_time of the medium's feeds is outside of a month;

* assign the language 'non' if there are more than 100 stories in the media source and no language is the majority.

=cut

sub set_primary_language($$)
{
    my ( $db, $medium ) = @_;

    my $primary_language = _detect_primary_language( $db, $medium );

    my $tag_set = get_primary_language_tag_set( $db );

    if ( !defined( $primary_language ) )
    {
        $db->query( <<SQL, $medium->{ media_id }, $tag_set->{ tag_sets_id } );
delete from media_tags_map mtm
    using tags t
    where
        mtm.media_id = \$1 and
        mtm.tags_id = t.tags_id and
        t.tag_sets_id = \$2
SQL
        return;
    }

    my $new_tag = get_primary_language_tag( $db, $primary_language );

    my $existing_tag = get_primary_language_tag_for_medium( $db, $medium );

    return if ( $existing_tag && ( $existing_tag->{ tags_id } == $new_tag->{ tags_id } ) );

    if ( $existing_tag )
    {
        $db->query( <<SQL, $existing_tag->{ tags_id }, $medium->{ media_id } );
delete from media_tags_map where tags_id = \$1 and media_id = \$2
SQL
    }

    $db->query( <<SQL, $new_tag->{ tags_id }, $medium->{ media_id } );
insert into media_tags_map ( tags_id, media_id ) values ( \$1, \$2 )
SQL

}

1;
