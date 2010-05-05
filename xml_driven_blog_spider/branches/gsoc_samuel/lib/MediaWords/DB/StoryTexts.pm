package MediaWords::DB::StoryTexts;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("story_texts");
__PACKAGE__->add_columns(
    "story_texts_id",
    {
        data_type     => "integer",
        default_value => "nextval('story_texts_story_texts_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "story_text",
    {
        data_type     => "text",
        default_value => undef,
        is_nullable   => 0,
        size          => undef,
    },
);
__PACKAGE__->set_primary_key("story_texts_id");
__PACKAGE__->add_unique_constraint( "story_texts_pkey", ["story_texts_id"] );
__PACKAGE__->has_many( "stories", "MediaWords::DB::Stories", { "foreign.story_texts_id" => "self.story_texts_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Oenv5prOsvMyVcF5J68m7g

# You can replace this text with custom content, and it will be preserved on regeneration
1;
