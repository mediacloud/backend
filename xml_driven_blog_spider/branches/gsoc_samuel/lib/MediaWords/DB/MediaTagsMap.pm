package MediaWords::DB::MediaTagsMap;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("media_tags_map");
__PACKAGE__->add_columns(
    "media_tags_map_id",
    {
        data_type     => "integer",
        default_value => "nextval('media_tags_map_media_tags_map_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "media_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
    "tags_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
);
__PACKAGE__->set_primary_key("media_tags_map_id");
__PACKAGE__->add_unique_constraint( "media_tags_map_media", [ "media_id", "tags_id" ] );
__PACKAGE__->add_unique_constraint( "media_tags_map_pkey", ["media_tags_map_id"] );
__PACKAGE__->belongs_to( "tags_id",  "MediaWords::DB::Tags",  { tags_id  => "tags_id" } );
__PACKAGE__->belongs_to( "media_id", "MediaWords::DB::Media", { media_id => "media_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Due+6EwzQ4zWAR0pYbbF3g

# You can replace this text with custom content, and it will be preserved on regeneration
1;
