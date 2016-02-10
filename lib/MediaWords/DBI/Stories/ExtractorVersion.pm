package MediaWords::DBI::Stories::ExtractorVersion;

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::Util::Tags;
use MediaWords::Util::ThriftExtractor;
use MediaWords::Util::ExtractorFactory;

# cached ids of tags, which should change rarely
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

    #Commit to make sure cache and database are consistent
    $db->dbh->{ AutoCommit } || $db->commit;

    $_tags_id_cache->{ $tag_sets_id }->{ $term } = $tag->{ tags_id };

    return $tag->{ tags_id };
}

sub _get_current_extractor_version
{
    my $config           = MediaWords::Util::Config::get_config;
    my $extractor_method = $config->{ mediawords }->{ extractor_method };

    my $extractor_version;

    if ( $extractor_method eq 'PythonReadability' )
    {
        $extractor_version = MediaWords::Util::ThriftExtractor::extractor_version();
    }
    else
    {
        my $old_extractor = MediaWords::Util::ExtractorFactory::createExtractor();
        $extractor_version = $old_extractor->extractor_version();
    }

    die unless defined( $extractor_version ) && $extractor_version;

    return $extractor_version;
}

my $_extractor_version_tag_set;

sub _get_extractor_version_tag_set
{

    my ( $db ) = @_;

    if ( !defined( $_extractor_version_tag_set ) )
    {
        $_extractor_version_tag_set = MediaWords::Util::Tags::lookup_or_create_tag_set( $db, "extractor_version" );
    }

    return $_extractor_version_tag_set;
}

sub get_current_extractor_version_tags_id
{
    my ( $db ) = @_;

    my $extractor_version = _get_current_extractor_version();
    my $tag_set           = _get_extractor_version_tag_set( $db );

    my $tags_id = _get_tags_id( $db, $tag_set->{ tag_sets_id }, $extractor_version );

    return $tags_id;
}

# add extractor version tag
sub update_extractor_version_tag
{
    my ( $db, $story ) = @_;

    my $tag_set = _get_extractor_version_tag_set( $db );

    $db->query( <<END, $tag_set->{ tag_sets_id }, $story->{ stories_id } );
delete from stories_tags_map stm
    using tags t
        join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id )
    where
        t.tags_id = stm.tags_id and
        ts.tag_sets_id = ? and
        stm.stories_id = ?
END

    my $tags_id = get_current_extractor_version_tags_id( $db );

    $db->query( <<END, $story->{ stories_id }, $tags_id );
insert into stories_tags_map ( stories_id, tags_id, db_row_last_updated ) values ( ?, ?, now() )
END

}

1;
