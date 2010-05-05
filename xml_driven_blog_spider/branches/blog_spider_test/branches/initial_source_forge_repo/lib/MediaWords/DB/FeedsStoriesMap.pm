package MediaWords::DB::FeedsStoriesMap;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("feeds_stories_map");
__PACKAGE__->add_columns(
    "feeds_stories_map_id",
    {
        data_type     => "integer",
        default_value => "nextval('feeds_stories_map_feeds_stories_map_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "feeds_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
    "stories_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
);
__PACKAGE__->set_primary_key("feeds_stories_map_id");
__PACKAGE__->add_unique_constraint( "feeds_stories_map_feed", [ "feeds_id", "stories_id" ] );
__PACKAGE__->add_unique_constraint( "feeds_stories_map_pkey", ["feeds_stories_map_id"] );
__PACKAGE__->belongs_to( "stories_id", "MediaWords::DB::Stories", { stories_id => "stories_id" }, );
__PACKAGE__->belongs_to( "feeds_id",   "MediaWords::DB::Feeds",   { feeds_id   => "feeds_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:qkNSXUGBKmTVkzYIGG9POg

# You can replace this text with custom content, and it will be preserved on regeneration
1;
