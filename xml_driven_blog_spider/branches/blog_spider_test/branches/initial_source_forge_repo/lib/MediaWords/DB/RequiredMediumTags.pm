package MediaWords::DB::RequiredMediumTags;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("required_medium_tags");
__PACKAGE__->add_columns(
    "required_medium_tags",
    {
        data_type         => "integer",
        default_value     => "nextval('public.required_medium_tags_required_medium_tags_seq'::text)",
        is_auto_increment => 1,
        is_nullable       => 0,
        size              => 4,
    },
    "media_id",
    {
        data_type      => "integer",
        default_value  => undef,
        is_foreign_key => 1,
        is_nullable    => 0,
        size           => 4,
    },
    "tag_sets_id",
    {
        data_type      => "integer",
        default_value  => undef,
        is_foreign_key => 1,
        is_nullable    => 0,
        size           => 4,
    },
);
__PACKAGE__->set_primary_key("required_medium_tags");
__PACKAGE__->add_unique_constraint( "required_medium_tags_medium", [ "media_id", "tag_sets_id" ] );
__PACKAGE__->add_unique_constraint( "required_medium_tags_pkey", ["required_medium_tags"] );
__PACKAGE__->belongs_to( "tag_sets_id", "MediaWords::DB::TagSets", { tag_sets_id => "tag_sets_id" }, );
__PACKAGE__->belongs_to( "media_id",    "MediaWords::DB::Media",   { media_id    => "media_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04999_02 @ 2008-04-14 11:56:28
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:AuuZmz5p756JSCkZJI9DLA

# You can replace this text with custom content, and it will be preserved on regeneration
1;
