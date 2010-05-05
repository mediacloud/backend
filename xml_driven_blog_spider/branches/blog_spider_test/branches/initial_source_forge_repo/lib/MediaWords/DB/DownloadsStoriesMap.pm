package MediaWords::DB::DownloadsStoriesMap;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("downloads_stories_map");
__PACKAGE__->add_columns(
    "downloads_stories_map_id",
    {
        data_type         => "integer",
        default_value     => "nextval('public.downloads_stories_map_downloads_stories_map_id_seq'::text)",
        is_auto_increment => 1,
        is_nullable       => 0,
        size              => 4,
    },
    "downloads_id",
    {
        data_type      => "integer",
        default_value  => undef,
        is_foreign_key => 1,
        is_nullable    => 0,
        size           => 4,
    },
    "stories_id",
    {
        data_type      => "integer",
        default_value  => undef,
        is_foreign_key => 1,
        is_nullable    => 0,
        size           => 4,
    },
);
__PACKAGE__->set_primary_key("downloads_stories_map_id");
__PACKAGE__->add_unique_constraint( "downloads_stories_map_pkey", ["downloads_stories_map_id"] );
__PACKAGE__->add_unique_constraint( "downloads_stories_map_download", [ "downloads_id", "stories_id" ], );
__PACKAGE__->belongs_to( "downloads_id", "MediaWords::DB::Downloads", { downloads_id => "downloads_id" }, );
__PACKAGE__->belongs_to( "stories_id",   "MediaWords::DB::Stories",   { stories_id   => "stories_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04999_02 @ 2008-03-17 10:47:50
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:H7dBkiIign4J7IMH/Z08xw

# You can replace this text with custom content, and it will be preserved on regeneration
1;
