package MediaWords::DBI::Stories;
use MediaWords::CommonLibs;

# various helper functions for stories

use strict;

use MediaWords::Util::BigPDLVector qw(vector_new vector_set vector_dot vector_normalize);
use MediaWords::Util::HTML;
use MediaWords::Tagger;
use MediaWords::Util::Config;
use MediaWords::DBI::StoriesTagsMapMediaSubtables;
use MediaWords::DBI::Downloads;
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

sub _get_full_text_from_rss
{
    my ( $db, $story ) = @_;

    my $ret = html_strip( $story->{ title } || '' ) . "\n" . html_strip( $story->{ description } || '' );

    return $ret;
}

# get the combined story title, story description, and download text of the text
sub _get_text_from_download_text
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

    if ( _has_full_text_rss( $db, $story ) )
    {
        return _get_full_text_from_rss( $db, $story );
    }

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

    return _get_text_from_download_text( $story, $download_texts );

}

# get extracted html of all the download texts associate with the story
sub get_extracted_html_from_db
{
    my ( $db, $story ) = @_;

    my $download_texts = $db->query(
        "select dt.* from download_texts dt, downloads d " .
          "  where dt.downloads_id = d.downloads_id and d.stories_id = ? " . "  order by d.downloads_id",
        $story->{ stories_id }
    )->hashes;

    return join( "\n", map { MediaWords::DBI::DownloadTexts::get_extracted_html_from_db( $db, $_ ) } @{ $download_texts } );
}

# Like get_text but it doesn't include both the rss information and the extracted text. Including both could cause some sentences to appear twice and throw off our word counts.
sub get_text_for_word_counts
{
    my ( $db, $story ) = @_;

    if ( _has_full_text_rss( $db, $story ) )
    {
        return _get_full_text_from_rss( $db, $story );
    }

    return get_extracted_text( $db, $story );
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

sub get_media_source_for_story
{
    my ( $db, $story ) = @_;

    my $medium = $db->query( "select * from media where media_id = ? ", $story->{ media_id } )->hash;

    return $medium;
}

sub update_rss_full_text_field
{
    my ( $db, $story ) = @_;

    my $medium = get_media_source_for_story( $db, $story );

    my $full_text_in_rss = 0;

    if ( $medium->{ full_text_rss } )
    {
        $full_text_in_rss = 1;
    }

    #This is a temporary hack to work around a bug in XML::FeedPP
    # Item description() will sometimes return a hash instead of text. In Handler.pm we replaced the hash ref with ''
    if ( length( $story->{ description } ) == 0 )
    {
        $full_text_in_rss = 0;
    }

    if ( defined( $story->{ full_text_rss } ) && ( $story->{ full_text_rss } != $full_text_in_rss ) )
    {
        $story->{ full_text_rss } = $full_text_in_rss;
        $db->query( "update stories set full_text_rss = ? where stories_id = ?", $full_text_in_rss, $story->{ stories_id } );
    }

    return $story;
}

sub _has_full_text_rss
{
    my ( $db, $story ) = @_;

    return $story->{ full_text_rss };
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

sub get_extracted_text
{
    my ( $db, $story ) = @_;

    my $download_texts = $db->query(
        "select dt.download_text from downloads d, download_texts dt " .
          "  where dt.downloads_id = d.downloads_id and d.stories_id = ? order by d.downloads_id",
        $story->{ stories_id }
    )->hashes;

    return join( ". ", map { $_->{ download_text } } @{ $download_texts } );
}

sub get_first_download_for_story
{
    my ( $db, $story ) = @_;

    my $download =
      $db->query( "select * from downloads where stories_id = ? order by downloads_id asc limit 1", $story->{ stories_id } )
      ->hash;

    return $download;
}

sub get_initial_download_content
{
    my ( $db, $story ) = @_;

    my $download = get_first_download_for_story( $db, $story );

    my $content = MediaWords::DBI::Downloads::fetch_content( $download );

    return $content;
}

# get word vectors for the top 1000 words for each story.
# add a { vector } field to each story where the vector for each
# query is the list of the counts of each word, with each word represented
# by an index value shared across the union of all words for all stories.
# if keep_words is true, also add a { words } field to each story
# with the list of words for each story in { stem => s, term => s, stem_count => s } form.
sub add_word_vectors
{
    my ( $db, $stories, $keep_words ) = @_;

    my $word_hash;

    my $i               = 0;
    my $next_word_index = 0;
    for my $story ( @{ $stories } )
    {
        print STDERR "add_word_vectors: " . $i++ . "[ $story->{ stories_id } ]\n";
        my $words = $db->query(
            "select ssw.stem, min( ssw.term ) term, sum( stem_count ) stem_count from story_sentence_words ssw " .
              "  where ssw.stories_id = ? " . "    and not is_stop_stem( 'short', ssw.stem ) " .
              "  group by ssw.stem order by sum( stem_count ) desc limit 1000 ",
            $story->{ stories_id }
        )->hashes;

        $story->{ vector } = [ 0 ];

        for my $word ( @{ $words } )
        {
            if ( !defined( $word_hash->{ $word->{ stem } } ) )
            {
                $word_hash->{ $word->{ stem } } = $next_word_index++;
            }

            my $word_index = $word_hash->{ $word->{ stem } };

            $story->{ vector }->[ $word_index ] = $word->{ stem_count };
        }

        if ( $keep_words )
        {
            print STDERR "keep words: " . scalar( @{ $words } ) . "\n";
            $story->{ words } = $words;
        }
    }

    return $stories;
}

# add a { similarities } field that holds the cosine similarity scores between each of the
# stories to each other story.  Also add a { vectors } field as generated by add_word_vectors above.
sub add_cos_similarities
{
    my ( $db, $stories ) = @_;

    return if ( !@{ $stories } );

    die( "must call add_word_vectors before add_cos_similarities" ) if ( !$stories->[ 0 ]->{ vector } );

    my $num_words = List::Util::max( map { scalar( @{ $_->{ vector } } ) } @{ $stories } );

    if ( $num_words )
    {
        print STDERR "add_cos_similarities: create normalized pdl vectors ";
        for my $story ( @{ $stories } )
        {
            print STDERR ".";
            my $pdl_vector = vector_new( $num_words );

            for my $i ( 0 .. $num_words - 1 )
            {
                vector_set( $pdl_vector, $i, $story->{ vector }->[ $i ] );
            }
            $story->{ pdl_norm_vector } = vector_normalize( $pdl_vector );
            $story->{ vector }          = undef;
        }
        print STDERR "\n";
    }

    print STDERR "add_cos_similarities: adding sims\n";
    for my $i ( 0 .. $#{ $stories } )
    {
        print STDERR "$i / $#{ $stories }: ";
        $stories->[ $i ]->{ cos }->[ $i ] = 1;

        for my $j ( $i + 1 .. $#{ $stories } )
        {
            print STDERR "." unless ( $j % 100 );
            my $sim = 0;
            if ( $num_words )
            {
                $sim = vector_dot( $stories->[ $i ]->{ pdl_norm_vector }, $stories->[ $j ]->{ pdl_norm_vector } );
            }

            $stories->[ $i ]->{ similarities }->[ $j ] = $sim;
            $stories->[ $j ]->{ similarities }->[ $i ] = $sim;
        }

        print STDERR "\n";
    }
}

1;
