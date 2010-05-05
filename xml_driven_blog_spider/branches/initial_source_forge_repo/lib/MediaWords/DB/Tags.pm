package MediaWords::DB::Tags;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("tags");
__PACKAGE__->add_columns(
    "tags_id",
    {
        data_type     => "integer",
        default_value => "nextval('tags_tags_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "tag_sets_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
    "tag",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 512,
    },
);
__PACKAGE__->set_primary_key("tags_id");
__PACKAGE__->add_unique_constraint( "tags_pkey", ["tags_id"] );
__PACKAGE__->add_unique_constraint( "tags_tag", [ "tag", "tag_sets_id" ] );
__PACKAGE__->has_many(
    "daily_feed_tag_counts",
    "MediaWords::DB::DailyFeedTagCounts",
    { "foreign.tags_id" => "self.tags_id" },
);
__PACKAGE__->has_many(
    "daily_feed_tag_tag_counts_tags_ids",
    "MediaWords::DB::DailyFeedTagTagCounts",
    { "foreign.tags_id" => "self.tags_id" },
);
__PACKAGE__->has_many(
    "daily_feed_tag_tag_counts_tag_tags_ids",
    "MediaWords::DB::DailyFeedTagTagCounts",
    { "foreign.tag_tags_id" => "self.tags_id" },
);
__PACKAGE__->has_many( "feeds_tags_maps",   "MediaWords::DB::FeedsTagsMap",   { "foreign.tags_id" => "self.tags_id" }, );
__PACKAGE__->has_many( "media_tags_maps",   "MediaWords::DB::MediaTagsMap",   { "foreign.tags_id" => "self.tags_id" }, );
__PACKAGE__->has_many( "stories_tags_maps", "MediaWords::DB::StoriesTagsMap", { "foreign.tags_id" => "self.tags_id" }, );
__PACKAGE__->belongs_to( "tag_sets_id", "MediaWords::DB::TagSets", { tag_sets_id => "tag_sets_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:hFg2UXXQ/db/1Y7CNVOQ1w

# You can replace this text with custom content, and it will be preserved on regeneration
1;
