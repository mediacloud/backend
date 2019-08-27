package MediaWords::Util::Tags;

# various functions for editing feed and medium tags
#
# FIXME move everything to "Tags" / "Tag sets" models?

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

# lookup the tag given the tag_set:tag format
sub lookup_tag
{
    my ( $db, $tag_name ) = @_;

    if ( $tag_name !~ /^([^:]*):(.*)$/ )
    {
        WARN "Unable to parse tag name '$tag_name'";
        return undef;
    }

    my ( $tag_set_name, $tag ) = ( $1, $2 );

    return $db->query(
        "select t.* from tags t, tag_sets ts where t.tag_sets_id = ts.tag_sets_id " . "    and t.tag = ? and ts.name = ?",
        $tag, $tag_set_name )->hash;
}

# lookup the tag given the tag_set:tag format.  create it if it does not already exist
sub lookup_or_create_tag
{
    my ( $db, $tag_name ) = @_;

    if ( $tag_name !~ /^([^:]*):(.*)$/ )
    {
        WARN "Unable to parse tag name '$tag_name'";
        return undef;
    }

    my ( $tag_set_name, $tag_tag ) = ( $1, $2 );

    my $tag_set = __lookup_or_create_tag_set( $db, $tag_set_name );
    my $tag = $db->find_or_create( 'tags', { tag => $tag_tag, tag_sets_id => $tag_set->{ tag_sets_id } } );

    return $tag;
}

# lookup the tag_set given.  create it if it does not already exist
sub __lookup_or_create_tag_set
{
    my ( $db, $tag_set_name ) = @_;

    my $tag_set = $db->find_or_create( 'tag_sets', { name => $tag_set_name } );

    return $tag_set;
}

# assign the given tag in the given tag_set to the given medium.  if the tag or tag_set does not exist, create it.
sub assign_singleton_tag_to_medium
{
    my ( $db, $medium, $tag_set, $tag ) = @_;

    $tag_set = $db->find_or_create( 'tag_sets', $tag_set );

    $tag->{ tag_sets_id } = $tag_set->{ tag_sets_id };

    # don't just use find_or_create here, because we want to find only on the actual tags.tag value, not the
    # rest of the tag metadata
    my $db_tag =
      $db->query( "select * from tags where tag_sets_id = ? and tag = ?", $tag->{ tag_sets_id }, $tag->{ tag } )->hash();
    if ( !$db_tag )
    {
        $db_tag = $db->create( 'tags', $tag );
    }

    $tag = $db_tag;

    # make sure we only update the tag in the db if necessary; otherwise we will trigger solr re-imports unnecessarily
    my $existing_tag = $db->query( <<SQL, $tag_set->{ tag_sets_id }, $medium->{ media_id } )->hash;
select t.* from tags t join media_tags_map mtm using ( tags_id ) where t.tag_sets_id = ? and mtm.media_id = ?
SQL

    return if ( $existing_tag && ( $existing_tag->{ tags_id } == $tag->{ tags_id } ) );

    if ( $existing_tag )
    {
        $db->query( <<SQL, $existing_tag->{ tags_id }, $medium->{ media_id } );
delete from media_tags_map where tags_id = ? and media_id = ?
SQL
    }

    $db->query( <<SQL, $tag->{ tags_id }, $medium->{ media_id } );
insert into media_tags_map ( tags_id, media_id ) values ( ?, ? )
    on conflict ( media_id, tags_id ) do nothing
SQL

}

1;
