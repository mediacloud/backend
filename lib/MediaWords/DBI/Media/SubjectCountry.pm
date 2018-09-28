package MediaWords::DBI::Media::SubjectCountry;

=head1 NAME

MediaWords::DBI::Media::SubjectCountry - functions for detecting and assigning the subject country to a media source

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;

use MediaWords::DBI::Media;
use MediaWords::Util::Tags;

# name of tag set that includes the story geotags
Readonly our $GEOTAG_TAG_SET_NAME => 'mc-geocoder@media.mit.edu';

# definition of tag set for media primary language
Readonly our $SUBJECT_COUNTRY_TAG_SET => {
    name        => 'subject_country',
    label       => 'Subject Country',
    description => 'Tags in this set indicate that a majority of the stories in the medium are about a country'
};

# min num of story tags in a medium that must be a given country
Readonly our $SUBJECT_COUNTRY_THRESHOLD => 0.50;

=head2 get_subject_country_tag_set( $db )

Return the tag_set containing the subject country tags

=cut

sub get_subject_country_tag_set($)
{
    my ( $db ) = @_;

    my $tag_set = $db->find_or_create( 'tag_sets', $SUBJECT_COUNTRY_TAG_SET );

    return $tag_set;
}

=head2 detect_subject_country( $db, $medium )

Query the database to detect the coountry that is the majority country tag for stories in the given media
source.  Return the country name.

=cut

sub detect_subject_country($$)
{
    my ( $db, $medium ) = @_;

    return undef unless ( MediaWords::DBI::Media::medium_is_ready_for_analysis( $db, $medium ) );

    DEBUG( "detecting subject_countries for $medium->{ name } ..." );

    my $tag_count = $db->query( <<SQL, $medium->{ media_id }, $GEOTAG_TAG_SET_NAME )->hash;
with subject_countries as (
    select
            s.stories_id,
            t.tags_id
        from stories s
            join stories_tags_map stm using ( stories_id )
            join tags t using ( tags_id )
            join tag_sets ts using ( tag_sets_id )
        where
            ts.name = \$2 and
            s.media_id = \$1
),

subject_country_counts as (
    select count(*) tag_count, tags_id from subject_countries group by tags_id
),

medium_stories_count as (
    select count( distinct stories_id ) story_count from subject_countries
)

select
        gc.tag_count,
        ( gc.tag_count::float / msc.story_count::float ) story_percent,
        t.*
    from subject_country_counts gc
        join tags t using ( tags_id )
        cross join medium_stories_count msc
    where
        ( gc.tag_count::float / msc.story_count::float ) > $SUBJECT_COUNTRY_THRESHOLD
    order by gc.tag_count desc
SQL

    my $country;
    if ( !$tag_count || ( $tag_count->{ story_percent } < $SUBJECT_COUNTRY_THRESHOLD ) )
    {
        $country = 'none';
    }
    else
    {
        $country = $tag_count->{ label };
        TRACE( "[ $tag_count->{ story_percent }  ]" );
    }

    DEBUG( "subject_country for $medium->{ name }: $country" );

    return $country;
}

=head2 set_subject_country( $db, $medium )

Assign to the media source the geo tag that is associated with the most stories and constitutes more than 50%
of the tags assigned to stories in that media source. If medium_is_ready_for_analysis() returns false, do nothing.
If medium_is_read_for_analysis returns true but no majority geo is found, assign the none tag.

Tags are assigned in the subject_country tag_set and are created as needed based on the data from the story
geotags tag_set.

=cut

sub set_subject_country($$)
{
    my ( $db, $medium ) = @_;

    my $subject_country = detect_subject_country( $db, $medium );

    my $description;
    if ( $subject_country eq 'none' )
    {
        $description = "Media sources for which there is no majority subject country.";
    }
    else
    {
        $description = "Media sources for which the majority subject country is $subject_country.";
    }

    my $tag = { tag => $subject_country, label => $subject_country, description => $description };

    MediaWords::Util::Tags::assign_singleton_tag_to_medium( $db, $medium, $SUBJECT_COUNTRY_TAG_SET, $tag );
}

=head2 get_untagged_media_ids( $db, $medium )

Get list of media that have no subject county tag.

=cut

sub get_untagged_media_ids($)
{
    my ( $db ) = @_;

    my $tag_set = get_subject_country_tag_set( $db );

    my $media_ids = $db->query( <<SQL, $tag_set->{ tag_sets_id } )->flat;
select m.media_id
    from media m
        left join (
            media_tags_map mtm
            join tags t on ( mtm.tags_id = t.tags_id and t.tag_sets_id = \$1 )
        ) on ( m.media_id = mtm.media_id )
    where
        t.tags_id is null
SQL

    return $media_ids;
}

1;
