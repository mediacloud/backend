package MediaWords::DB::DailyFeedTagTagCounts;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("daily_feed_tag_tag_counts");
__PACKAGE__->add_columns(
    "daily_feed_tag_tag_counts_id",
    { data_type => "bigint", default_value => undef, is_nullable => 0, size => 8 },
    "tag_count",
    { data_type => "bigint", default_value => undef, is_nullable => 1, size => 8 },
    "tags_id",
    { data_type => "integer", default_value => undef, is_nullable => 1, size => 4 },
    "tag_tags_id",
    { data_type => "integer", default_value => undef, is_nullable => 1, size => 4 },
    "feeds_id",
    { data_type => "integer", default_value => undef, is_nullable => 1, size => 4 },
    "publish_day",
    {
        data_type     => "timestamp without time zone",
        default_value => undef,
        is_nullable   => 1,
        size          => 8,
    },
);
__PACKAGE__->set_primary_key("daily_feed_tag_tag_counts_id");
__PACKAGE__->add_unique_constraint( "daily_feed_tag_tag_counts_pkey", ["daily_feed_tag_tag_counts_id"], );
__PACKAGE__->belongs_to( "feeds_id",    "MediaWords::DB::Feeds", { feeds_id => "feeds_id" }, );
__PACKAGE__->belongs_to( "tags_id",     "MediaWords::DB::Tags",  { tags_id  => "tags_id" } );
__PACKAGE__->belongs_to( "tag_tags_id", "MediaWords::DB::Tags",  { tags_id  => "tag_tags_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:QdC5keLHcx8N7lhtTY0sgg

# You can replace this text with custom content, and it will be preserved on regeneration
1;
