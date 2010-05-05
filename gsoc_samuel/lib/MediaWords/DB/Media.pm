package MediaWords::DB::Media;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("media");
__PACKAGE__->add_columns(
    "media_id",
    {
        data_type     => "integer",
        default_value => "nextval('media_media_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "url",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 1024,
    },
    "name",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 128,
    },
);
__PACKAGE__->set_primary_key("media_id");
__PACKAGE__->add_unique_constraint( "media_pkey", ["media_id"] );
__PACKAGE__->add_unique_constraint( "media_name", ["name"] );
__PACKAGE__->add_unique_constraint( "media_url",  ["url"] );
__PACKAGE__->has_many( "feeds",           "MediaWords::DB::Feeds",        { "foreign.media_id" => "self.media_id" }, );
__PACKAGE__->has_many( "media_tags_maps", "MediaWords::DB::MediaTagsMap", { "foreign.media_id" => "self.media_id" }, );
__PACKAGE__->has_many( "stories",         "MediaWords::DB::Stories",      { "foreign.media_id" => "self.media_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:3h8yAJrOYEotUTt1YTWDgQ

# return space joined list of tags
sub medium_tags_string
{
    my ($self) = @_;

    return join( ' ', map { $_->tags_id->tag_sets_id->name . ':' . $_->tags_id->tag } $self->media_tags_maps );
}

# You can replace this text with custom content, and it will be preserved on regeneration
1;
