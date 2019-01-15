package MediaWords::Util::Tags;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.util.tags' );

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

    my $tag_set = $db->find_or_create( 'tag_sets', { 'name' => $tag_set_name } );
    my $tag = $db->find_or_create( 'tags', { tag => $tag_tag, tag_sets_id => $tag_set->{ tag_sets_id } } );

    return $tag;
}

# assign the given tag in the given tag_set to the given medium.  if the tag or tag_set does not exist, create it.
sub assign_singleton_tag_to_medium
{
    my ( $db, $medium, $tag_set, $tag ) = @_;

    $tag_set = $db->find_or_create( 'tag_sets', $tag_set );

    $tag->{ tag_sets_id } = $tag_set->{ tag_sets_id };

    $tag = $db->find_or_create( 'tags', $tag );

    # make sure we only update the tag in the db if necessary; otherwise we will trigger solr re-imports unnecessarily
    my $existing_tag = $db->query( <<SQL, $tag_set->{ tag_sets_id }, $medium->{ media_id } )->hash;
select t.* from tags t join media_tags_map mtm using ( tags_id ) where t.tag_sets_id = \$1 and mtm.media_id = \$2
SQL

    return if ( $existing_tag && ( $existing_tag->{ tags_id } == $tag->{ tags_id } ) );

    if ( $existing_tag )
    {
        $db->query( <<SQL, $existing_tag->{ tags_id }, $medium->{ media_id } );
delete from media_tags_map where tags_id = \$1 and media_id = \$2
SQL
    }

    $db->query( <<SQL, $tag->{ tags_id }, $medium->{ media_id } );
insert into media_tags_map ( tags_id, media_id ) values ( \$1, \$2 )
SQL

}

1;
