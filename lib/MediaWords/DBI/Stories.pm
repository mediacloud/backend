package MediaWords::DBI::Stories;

# various helper functions for stories

use strict;

use MediaWords::Util::HTML;
use MediaWords::Tagger;
use MediaWords::Util::Config;
use MediaWords::DBI::StoriesTagsMapMediaSubtables;
use List::Compare;

my $_tags_id_cache = {};

# get cached id of the tag.  create the tag if necessary.
# we need this to make tag lookup very fast for add_default_tags
sub _get_tags_id
{
    my ( $db, $tag_sets_id, $term ) = @_;

    if ( $_tags_id_cache->{ $tag_sets_id }->{ $term } )
    {
        return $_tags_id_cache->{ $tag_sets_id }->{ $term };
    }

    my $tag = $db->find_or_create(
        'tags',
        {
            tag         => $term,
            tag_sets_id => $tag_sets_id
        }
    );

    $_tags_id_cache->{ $tag_sets_id }->{ $term } = $tag->{ tags_id };

    return $tag->{ tags_id };
}

# get the combined story title, story description, and download text of the text
sub get_text_from_download_text
{
    my ( $story, $download_texts ) = @_;

    return join( "\n***\n\n",
        html_strip( $story->{ title }       || '' ),
        html_strip( $story->{ description } || '' ),
        @{ $download_texts } );
}

# get the concatenation of the story title and description and all of the download_texts associated with the story
sub get_text
{
    my ( $db, $story ) = @_;

    my $download_texts = $db->query(
        "select download_text from download_texts dt, downloads d " .
          "  where d.downloads_id = dt.downloads_id and d.stories_id = ? " . "  order by d.downloads_id asc",
        $story->{ stories_id }
    )->flat;

    my $pending_download =
      $db->query( "select downloads_id from downloads " . "  where extracted = 'f' and stories_id = ? and type = 'content' ",
        $story->{ stories_id } )->hash;

    if ( $pending_download )
    {
        push( @{ $download_texts }, "(downloads pending extraction)" );
    }

    my ( $title, $description ) =
      $db->query( "select title, description from stories where stories_id = ?", $story->{ stories_id } )->flat;

    return get_text_from_download_text( $story, $download_texts );

}

# store any content returned by the tagging module in the downloads table
sub _store_tags_content
{
    my ( $db, $story, $module, $tags ) = @_;

    if ( !$tags->{ content } )
    {
        return;
    }

    my $download = $db->query(
        "select * from downloads where stories_id = ? and type = 'content' " . "  order by downloads_id asc limit 1",
        $story->{ stories_id } )->hash;

    my $tags_download = $db->create(
        'downloads',
        {
            feeds_id      => $download->{ feeds_id },
            stories_id    => $story->{ stories_id },
            parent        => $download->{ downloads_id },
            url           => $download->{ url },
            host          => $download->{ host },
            download_time => 'now()',
            type          => $module,
            state         => 'pending',
            priority      => 10,
            sequence      => 1
        }
    );

    #my $content = $tags->{content};

    MediaWords::DBI::Downloads::store_content( $db, $tags_download, \$tags->{ content } );
}

sub get_existing_tags
{
    my ( $db, $story, $module ) = @_;

    my $tag_set = $db->find_or_create( 'tag_sets', { name => $module } );

    my $ret = $db->query(
"SELECT stm.tags_id FROM stories_tags_map stm, tags where stories_id = ? and stm.tags_id=tags.tags_id and tags.tag_sets_id = ?",
        $story->{ stories_id },
        $tag_set->{ tag_sets_id }
    )->flat;

    return $ret;
}

# add a tags list as returned by MediaWords::Tagger::get_tags_for_modules to the database.
# handle errors from the tagging module.
# store any content returned by the tagging module.
sub _add_module_tags
{
    my ( $db, $story, $module, $tags ) = @_;

    if ( !$tags->{ tags } )
    {
        print STDERR "tagging error - module: $module story: $story->{stories_id} error: $tags->{error}\n";
        return;
    }

    my $tag_set = $db->find_or_create( 'tag_sets', { name => $module } );

    $db->query(
        "delete from stories_tags_map as stm using tags t " .
          "  where stm.tags_id = t.tags_id and t.tag_sets_id = ? and stm.stories_id = ? ",
        $tag_set->{ tag_sets_id },
        $story->{ stories_id }
    );

    my @terms = @{ $tags->{ tags } };

    #print STDERR "tags [$module]: " . join( ',', map { "<$_>" } @terms ) . "\n";

    my @tags_ids = map { _get_tags_id( $db, $tag_set->{ tag_sets_id }, $_ ) } @terms;

    #my $existing_tags = _get_existing_tags( $db, $story, $module );
    #my $lc = List::Compare->new( \@tags_ids, $existing_tags );
    #@tags_ids = $lc->get_Lonly();

    $db->dbh->do( "copy stories_tags_map (stories_id, tags_id) from STDIN" );
    for my $tags_id ( @tags_ids )
    {
        $db->dbh->pg_putcopydata( $story->{ stories_id } . "\t" . $tags_id . "\n" );
    }

    $db->dbh->pg_endcopy();

    my $media_id = $story->{ media_id };
    my $subtable_name =
      MediaWords::DBI::StoriesTagsMapMediaSubtables::get_or_create_sub_table_name_for_media_id( $media_id );

    $db->query(
        "delete from $subtable_name stm using tags t " .
          "  where stm.tags_id = t.tags_id and t.tag_sets_id = ? and stm.stories_id = ? ",
        $tag_set->{ tag_sets_id },
        $story->{ stories_id }
    );

    $db->dbh->do( "copy $subtable_name (media_id, publish_date, stories_id, tags_id, tag_sets_id) from STDIN" );
    for my $tags_id ( @tags_ids )
    {
        my $put_statement =
          join( "\t", $media_id, $story->{ publish_date }, $story->{ stories_id }, $tags_id, $tag_set->{ tag_sets_id } ) .
          "\n";
        $db->dbh->pg_putcopydata( $put_statement );
    }
    $db->dbh->pg_endcopy();

    _store_tags_content( $db, $story, $module, $tags );
}

# add tags for all default modules to the story in the database.
# handle errors and store any content returned by the tagging module.
sub add_default_tags
{
    my ( $db, $story ) = @_;

    my $text = get_text( $db, $story );

    my $default_tag_modules_list = MediaWords::Util::Config::get_config->{ mediawords }->{ default_tag_modules };
    $default_tag_modules_list ||= 'NYTTopics';

    my $default_tag_modules = [ split( /[,\s+]/, $default_tag_modules_list ) ];

    my $module_tags = MediaWords::Tagger::get_tags_for_modules( $text, $default_tag_modules );

    for my $module ( keys( %{ $module_tags } ) )
    {
        _add_module_tags( $db, $story, $module, $module_tags->{ $module } );
    }

    return $module_tags;
}

# query the download and call fetch_content
sub fetch_content
{
    my ( $db, $story ) = @_;

    my $download = $db->query( "select * from downloads where stories_id = ?", $story->{ stories_id } )->hash;
    return MediaWords::DBI::Downloads::fetch_content( $download );
}

# get the tags for the given module associated with the given story from the db
sub get_db_module_tags
{
    my ( $db, $story, $module ) = @_;

    my $tag_set = $db->find_or_create( 'tag_sets', { name => $module } );

    return $db->query(
        "SELECT t.* FROM stories_tags_map stm, tags t, tag_sets ts " .
          "  where stm.stories_id = ? and stm.tags_id = t.tags_id " .
          "    and t.tag_sets_id = ts.tag_sets_id and ts.name = ?",
        $story->{ stories_id },
        $module
    )->hashes;
}

1;
