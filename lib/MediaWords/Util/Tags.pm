package MediaWords::Util::Tags;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.util.tags' );

use YAML::Syck;

# return a hash with keys of each tag id associated with the object
sub _get_tags_lookup
{
    my ( $c, $oid, $oid_field, $map_table ) = @_;

    if ( !$oid )
    {
        return {};
    }

    my @maps = $c->dbis->query( "select * from $map_table where $oid_field = ?", $oid )->hashes;

    my $lookup;
    for my $map ( @maps )
    {
        $lookup->{ $map->{ tags_id } } = 1;
    }

    return $lookup;
}

# make edit tags form in real time by running yml template through template toolkit
sub make_edit_tags_form
{
    my ( $c, $action, $oid, $table ) = @_;

    my $oid_field = "${table}_id";

    my $map_table = "${table}_tags_map";

    my @tag_sets =
      $c->dbis->query( "select distinct ts.* from tag_sets ts, tags t, $map_table m " .
          "where ts.tag_sets_id = t.tag_sets_id and t.tags_id = m.tags_id and " .
          "m.tags_id is not null " . "order by ts.name" )->hashes;

    for my $tag_set ( @tag_sets )
    {
        $tag_set->{ tags } =
          $c->dbis->query( "select * from tags where tag_sets_id = $tag_set->{tag_sets_id} order by tag" )->hashes;
    }

    my $tags_lookup = _get_tags_lookup( $c, $oid, $oid_field, $map_table );

    my $vars = {
        tag_sets    => \@tag_sets,
        tags_lookup => $tags_lookup,
        new_tags    => 1

    };

    my $yaml;
    my $template = Template->new( ABSOLUTE => 1 );
    if ( !( $template->process( $c->path_to . '/root/forms/edit_tags.yml.tt2', $vars, \$yaml ) ) )
    {
        die( "Unable to process template: " . $template->error() );
    }

    my $form = $c->create_form(
        {
            method => 'post',
            action => $action
        }
    );

    #TODO replace YAML::Syck with another module
    my $config_data = YAML::Syck::Load( $yaml );
    $form->populate( $config_data );

    $form->process( $c->request );

    return $form;
}

# save tag info for the given object (medium or feed) from edit_tags form.  return list of
# tag ids, including ids of any new tags created.  if no object is given, just create
# any new tags indicated,  if $append is true, append tags to existing ones
sub save_tags
{
    my ( $c, $oid, $table, $append ) = @_;

    my $oid_field = "${table}_id";

    my $tag_ids = [ $c->request->param( 'tags' ) ];

    for my $tag_set ( $c->dbis->query( "select * from tag_sets" )->hashes )
    {
        if ( my $new_tag_string = int( $c->request->param( 'new_tags_' . $tag_set->{ tag_sets_id } ) ) )
        {
            for my $new_tag_name ( map { lc( $_ ) } split( /\s+/, $new_tag_string ) )
            {
                my $new_tag =
                  $c->dbis->find_or_create( 'tags', { tag => $new_tag_name, tag_sets_id => $tag_set->{ tag_sets_id } } );
                push( @{ $tag_ids }, $new_tag->{ tags_id } );
            }
        }
    }

    if ( my $new_tag_set_name = $c->request->param( 'new_tag_set' ) )
    {
        $new_tag_set_name =~ s/\s+/_/g;
        $new_tag_set_name = lc( $new_tag_set_name );
        my $new_tag_set = $c->dbis->find_or_create( 'tag_sets', { name => $new_tag_set_name } );

        for my $new_tag_name ( map { lc( $_ ) } split( /\s+/, $c->request->param( 'new_tag_set_tags' ) ) )
        {
            my $new_tag =
              $c->dbis->find_or_create( 'tags', { tag => $new_tag_name, tag_sets_id => $new_tag_set->{ tag_sets_id } } );
            push( @{ $tag_ids }, $new_tag->{ tags_id } );
        }
    }

    if ( $oid )
    {
        if ( !$append )
        {
            $c->dbis->query( "delete from ${table}_tags_map where $oid_field = ?", $oid );
        }

        for my $tags_id ( @{ $tag_ids } )
        {
            my $tag_exists = $c->dbis->query( <<END, $tags_id, $oid )->hash;
select * from ${ table }_tags_map where tags_id = ? and oid_field = ?
END
            if ( !$tag_exists )
            {
                $c->dbis->create( "${table}_tags_map", { tags_id => $tags_id, $oid_field => $oid } );
            }
        }
    }

    return $tag_ids;
}

# save tag info for the given object (medium or feed) from a space separated list of tag names.
# oid is the object id (eg the media_id), and table is the name of the table for which to save
# the tag associations (eg media).
sub save_tags_by_name
{
    my ( $db, $oid, $table, $tag_names_list ) = @_;

    my $oid_field = "${table}_id";

    my $tag_names = [ split( /\s*,\s*/, $tag_names_list ) ];

    my $tags = [];
    map { push( @{ $tags }, lookup_or_create_tag( $db, $_ ) ) } @{ $tag_names };

    $db->query( "delete from ${ table }_tags_map where ${ table }_id = ?", $oid );

    for my $tag ( @{ $tags } )
    {
        my $tag_exists = $db->query( <<END, $tag->{ tags_id }, $oid )->hash;
select * from ${ table }_tags_map where tags_id = ? and ${ table }_id = ?
END
        if ( !$tag_exists )
        {
            $db->create( "${table}_tags_map", { tags_id => $tag->{ tags_id }, $oid_field => $oid } );
        }
    }
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

    my $tag_set = lookup_or_create_tag_set( $db, $tag_set_name );
    my $tag = $db->find_or_create( 'tags', { tag => $tag_tag, tag_sets_id => $tag_set->{ tag_sets_id } } );

    return $tag;
}

# lookup the tag_set given.  create it if it does not already exist
sub lookup_or_create_tag_set
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
