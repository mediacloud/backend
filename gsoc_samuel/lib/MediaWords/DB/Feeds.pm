package MediaWords::DB::Feeds;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("feeds");
__PACKAGE__->add_columns(
    "feeds_id",
    {
        data_type     => "integer",
        default_value => "nextval('feeds_feeds_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "media_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
    "name",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 512,
    },
    "url",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 1024,
    },
    "reparse",
    { data_type => "boolean", default_value => undef, is_nullable => 1, size => 1 },
    "last_download_time",
    {
        data_type     => "timestamp without time zone",
        default_value => undef,
        is_nullable   => 1,
        size          => 8,
    },
);
__PACKAGE__->set_primary_key("feeds_id");
__PACKAGE__->add_unique_constraint( "feeds_url", [ "url", "media_id" ] );
__PACKAGE__->add_unique_constraint( "feeds_pkey", ["feeds_id"] );
__PACKAGE__->has_many(
    "daily_feed_tag_counts",
    "MediaWords::DB::DailyFeedTagCounts",
    { "foreign.feeds_id" => "self.feeds_id" },
);
__PACKAGE__->has_many(
    "daily_feed_tag_tag_counts",
    "MediaWords::DB::DailyFeedTagTagCounts",
    { "foreign.feeds_id" => "self.feeds_id" },
);
__PACKAGE__->has_many( "downloads", "MediaWords::DB::Downloads", { "foreign.feeds_id" => "self.feeds_id" }, );
__PACKAGE__->belongs_to( "media_id", "MediaWords::DB::Media", { media_id => "media_id" }, );
__PACKAGE__->has_many( "feeds_stories_maps", "MediaWords::DB::FeedsStoriesMap", { "foreign.feeds_id" => "self.feeds_id" }, );
__PACKAGE__->has_many( "feeds_tags_maps",    "MediaWords::DB::FeedsTagsMap",    { "foreign.feeds_id" => "self.feeds_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:KfDJzguRHIaZVCOnSkvbLA
# return space joined list of tags

# get where clause that returns only feeds that haven't had a download
# within interval seconds
sub get_stale_feeds_clause
{
    my ( $self, $interval ) = @_;

    my $where_clause = qq~
( not exists
    ( select 1 from downloads d
        where d.feeds_id = me.feeds_id and d.type = 'feed'
        group by d.feeds_id
        having max(download_time) > now() - interval '$interval seconds'
    )
)
~;

    return \$where_clause;
}

# get string concatenation of feed tags
sub feed_tags_string
{
    my ($self) = @_;

    return join( ' ', map { $_->tags_id->tag_sets_id->name . ':' . $_->tags_id->tag } $self->feeds_tags_maps );
}

1;
