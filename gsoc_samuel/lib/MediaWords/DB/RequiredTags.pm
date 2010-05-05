package MediaWords::DB::RequiredTags;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("required_tags");
__PACKAGE__->add_columns(
    "required_tags_id",
    {
        data_type         => "integer",
        default_value     => "nextval('public.required_tags_required_tags_id_seq'::text)",
        is_auto_increment => 1,
        is_nullable       => 0,
        size              => 4,
    },
    "table_name",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 256,
    },
    "tag_prefix",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 256,
    },
);
__PACKAGE__->set_primary_key("required_tags_id");
__PACKAGE__->add_unique_constraint( "required_tags_pkey", ["required_tags_id"] );
__PACKAGE__->add_unique_constraint( "required_tags_table_name", [ "table_name", "tag_prefix" ] );

# Created by DBIx::Class::Schema::Loader v0.04999_02 @ 2008-05-28 12:08:00
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:vVWwG1Zu9YKkteYD6PjaGw

# You can replace this text with custom content, and it will be preserved on regeneration
1;
