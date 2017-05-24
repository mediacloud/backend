package MediaWords::DBI::Media::PrimaryLanguage;

=head1 NAME

MediaWords::DBI::Media - functions for detecting and assigning the primary language to a media source

=cut

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Media;
use MediaWords::Util::IdentifyLanguage;
use MediaWords::Util::Tags;

use Readonly;

# definition of tag set for media primary language
Readonly our $PRIMARY_LANGUAGE_TAG_SET => {
    name        => 'primary_language',
    label       => 'Primary Language',
    description => 'Tags in this set indicate that most stories in the media source are in the language.'
};

# min num of stories that must be identified as a language for it to be the primary language of the medium
Readonly our $PRIMARY_LANGUAGE_THRESHOLD => 0.50;

=head1 FUNCTIONS

=cut

# detect the primary language of the media source, as described in set_primary_language below
sub detect_primary_language($$)
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

    return 'none' unless ( $total_count > 0 );

    my $proportion = $first_language->{ count } / $total_count;

    my $primary_language = $proportion > $PRIMARY_LANGUAGE_THRESHOLD ? $first_language->{ language } : 'none';

    DEBUG( "detect primary language for $medium->{ name } [$media_id] update to $primary_language" );

    return $primary_language || 'none';

}

=head2 get_primary_language_tag_set( $db )

Return the tag_set containing the primary language tags.

=cut

sub get_primary_language_tag_set($)
{
    my ( $db ) = @_;

    my $tag_set = $db->find_or_create( 'tag_sets', $PRIMARY_LANGUAGE_TAG_SET );

    return $tag_set;
}

=head2 set_primary_language( $db, $medium )

Assign a $PRIMAY_LANGUAGE_TAG_SET_NAME: tag to the media source as the language of the greatest number of stories in the
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

    my $primary_language = detect_primary_language( $db, $medium );

    return unless $primary_language;

    my $label = MediaWords::Util::IdentifyLanguage::language_name_for_code( $primary_language );
    $label ||= $primary_language;

    my $description = "Media sources for which the primary language is $label";

    my $tag = { tag => $primary_language, label => $label, description => $description };

    MediaWords::Util::Tags::assign_singleton_tag_to_medium( $db, $medium, $PRIMARY_LANGUAGE_TAG_SET, $tag );
}

=head2 get_untagged_media_ids( $db, $medium )

Get list of media that have no primary language tag.

=cut

sub get_untagged_media_ids($)
{
    my ( $db ) = @_;

    my $tag_set = get_primary_language_tag_set( $db );

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
