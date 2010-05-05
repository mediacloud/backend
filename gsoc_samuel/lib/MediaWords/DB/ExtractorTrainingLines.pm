package MediaWords::DB::ExtractorTrainingLines;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("extractor_training_lines");
__PACKAGE__->add_columns(
    "extractor_training_lines_id",
    {
        data_type     => "integer",
        default_value => "nextval('extractor_training_lines_extractor_training_lines_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "line_number",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
    "required",
    { data_type => "boolean", default_value => undef, is_nullable => 0, size => 1 },
    "downloads_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
);
__PACKAGE__->set_primary_key("extractor_training_lines_id");
__PACKAGE__->add_unique_constraint( "extractor_training_lines_line", [ "line_number", "downloads_id" ], );
__PACKAGE__->add_unique_constraint( "extractor_training_lines_pkey", ["extractor_training_lines_id"], );
__PACKAGE__->belongs_to( "downloads_id", "MediaWords::DB::Downloads", { downloads_id => "downloads_id" }, );

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:10fgw/fgZ4zJDPATJq2w3g

# You can replace this text with custom content, and it will be preserved on regeneration
1;
