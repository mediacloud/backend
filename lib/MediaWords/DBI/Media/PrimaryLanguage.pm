package MediaWords::DBI::Media::PrimaryLanguage;

=head1 NAME

MediaWords::DBI::Media - functions for detecting and assigning the primary language to a media source

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::IdentifyLanguage;

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

# min num of stories that must be identified as a language for it to be the primary language of the medium
Readonly my $PRIMARY_LANGUAGE_THRESHOLD => 0.50;

=head1 FUNCTIONS

=cut

# detect the primary language of the media source, as described in set_primary_language below
sub _detect_primary_language($$)
{
    my ( $db, $medium ) = @_;

    return undef unless ( MediaWords::DBI::Media::medium_is_ready_for_analysis( $db, $medium ) );

    my $media_id = $medium->{ media_id };

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

    my $proportion = $first_language->{ count } / $total_count;

    my $primary_language = $proportion > $PRIMARY_LANGUAGE_THRESHOLD ? $first_language->{ language } : 'none';

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

* assign no tag if MediaWords::DBI::Media::medium_is_ready_for_analysis() returns false;

* assign the majority story language if MediaWords::DBI::Media::medium_is_ready_for_analysis() returns true;

* assign 'none' if MediaWords::DBI::Media::medium_is_ready_for_analysis() returns true and there is no majority story language.

=cut

sub set_primary_language($$)
{
    my ( $db, $medium ) = @_;

    my $primary_language = _detect_primary_language( $db, $medium );

    my $tag_set = get_primary_language_tag_set( $db );

    if ( !$primary_language )
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

    # make sure we only update the tag in the db if necessary; otherwise we will trigger solr re-imports unnecessarily
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
