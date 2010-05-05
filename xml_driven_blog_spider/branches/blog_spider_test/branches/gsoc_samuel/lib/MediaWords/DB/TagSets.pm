package MediaWords::DB::TagSets;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("tag_sets");
__PACKAGE__->add_columns(
    "tag_sets_id",
    {
        data_type     => "integer",
        default_value => "nextval('tag_sets_tag_sets_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "name",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 512,
    },
);
__PACKAGE__->set_primary_key("tag_sets_id");
__PACKAGE__->add_unique_constraint( "tag_sets_pkey", ["tag_sets_id"] );
__PACKAGE__->add_unique_constraint( "tag_sets_name", ["name"] );
__PACKAGE__->has_many( "tags", "MediaWords::DB::Tags", { "foreign.tag_sets_id" => "self.tag_sets_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:yC6kIxEc2xoZLSAFFqPcbQ

# You can replace this text with custom content, and it will be preserved on regeneration
1;
