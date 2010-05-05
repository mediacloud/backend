package MediaWords::DB::StoriesTagsMap;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("stories_tags_map");
__PACKAGE__->add_columns(
    "stories_tags_map_id",
    {
        data_type     => "integer",
        default_value => "nextval('stories_tags_map_stories_tags_map_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "stories_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
    "tags_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
);
__PACKAGE__->set_primary_key("stories_tags_map_id");
__PACKAGE__->add_unique_constraint( "stories_tags_map_story", [ "stories_id", "tags_id" ] );
__PACKAGE__->add_unique_constraint( "stories_tags_map_pkey", ["stories_tags_map_id"] );
__PACKAGE__->belongs_to( "stories_id", "MediaWords::DB::Stories", { stories_id => "stories_id" }, );
__PACKAGE__->belongs_to( "tags_id",    "MediaWords::DB::Tags",    { tags_id    => "tags_id" } );

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:EuJN+w0Mhsr5UHZicz3ahQ

# You can replace this text with custom content, and it will be preserved on regeneration
1;
