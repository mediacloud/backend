package MediaWords::Util::Tags;

# various functions for editing feed and medium tags

use strict;

# return a hash with keys of each tag id associated with the object
sub get_tags_lookup
{
    my ( $class, $c, $oid, $oid_field, $map_table ) = @_;

    if ( !$oid )
    {
        return {};
    }

    my @maps = $c->dbis->query( "select * from $map_table where $oid_field = ?", $oid )->hashes;

    my $lookup;
    for my $map (@maps)
    {
        $lookup->{ $map->{tags_id} } = 1;
    }

    return $lookup;
}

# make edit tags form in real time by running yml template through template toolkit
sub make_edit_tags_form
{
    my ( $class, $c, $action, $oid, $table ) = @_;

    my $oid_field = "${table}_id";

    my $map_table = "${table}_tags_map";

    my @tag_sets =
      $c->dbis->query( "select distinct ts.* from tag_sets ts, tags t, $map_table m "
          . "where ts.tag_sets_id = t.tag_sets_id and t.tags_id = m.tags_id and "
          . "m.tags_id is not null "
          . "order by ts.name" )->hashes;

    for my $tag_set (@tag_sets)
    {
        $tag_set->{tags} =
          $c->dbis->query( "select * from tags where tag_sets_id = $tag_set->{tag_sets_id} order by tag" )->hashes;
    }

    my $tags_lookup = $class->get_tags_lookup( $c, $oid, $oid_field, $map_table );

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

    my $form = HTML::FormFu->new(
        {
            method => 'POST',
            action => $action
        }
    );

    my $config_data = YAML::Syck::Load($yaml);
    $form->populate($config_data);

    $form->process( $c->request );

    return $form;
}

# save tag info for the given object (medium or feed) from edit_tags form.  return list of
# tag ids, including ids of any new tags created.  if no object is given, just create
# any new tags indicated,  if $append is true, append tags to existing ones
sub save_tags
{
    my ( $class, $c, $oid, $table, $append ) = @_;

    my $oid_field = "${table}_id";

    my $tag_ids = [ $c->request->param('tags') ];

    for my $tag_set ( $c->dbis->query("select * from tag_sets")->hashes )
    {
        if ( my $new_tag_string = $c->request->param( 'new_tags_' . $tag_set->{tag_sets_id} ) )
        {
            for my $new_tag_name ( map { lc($_) } split( /\s+/, $new_tag_string ) )
            {
                my $new_tag =
                  $c->dbis->find_or_create( 'tags', { tag => $new_tag_name, tag_sets_id => $tag_set->{tag_sets_id} } );
                push( @{$tag_ids}, $new_tag->{tags_id} );
            }
        }
    }

    if ( my $new_tag_set_name = $c->request->param('new_tag_set') )
    {
        $new_tag_set_name =~ s/\s+/_/g;
        $new_tag_set_name = lc($new_tag_set_name);
        my $new_tag_set = $c->dbis->find_or_create( 'tag_sets', { name => $new_tag_set_name } );

        for my $new_tag_name ( map { lc($_) } split( /\s+/, $c->request->param('new_tag_set_tags') ) )
        {
            my $new_tag =
              $c->dbis->find_or_create( 'tags', { tag => $new_tag_name, tag_sets_id => $new_tag_set->{tag_sets_id} } );
            push( @{$tag_ids}, $new_tag->{tags_id} );
        }
    }

    if ($oid)
    {
        if ( !$append )
        {
            $c->dbis->query( "delete from ${table}_tags_map where $oid_field = ?", $oid );
        }

        for my $tags_id ( @{$tag_ids} )
        {
            eval { $c->dbis->create( "${table}_tags_map", { tags_id => $tags_id, $oid_field => $oid } ) };
            if ( $@ && ( $@ !~ /unique constraint/ ) )
            {
                die($@);
            }
        }
    }

    return $tag_ids;
}

1;
