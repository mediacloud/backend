package MediaWords::DB::Stories;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("stories");
__PACKAGE__->add_columns(
    "stories_id",
    {
        data_type     => "integer",
        default_value => "nextval('stories_stories_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "media_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
    "url",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 1024,
    },
    "guid",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 1024,
    },
    "title",
    {
        data_type     => "text",
        default_value => undef,
        is_nullable   => 0,
        size          => undef,
    },
    "description",
    {
        data_type     => "text",
        default_value => undef,
        is_nullable   => 1,
        size          => undef,
    },
    "publish_date",
    {
        data_type     => "timestamp without time zone",
        default_value => undef,
        is_nullable   => 0,
        size          => 8,
    },
    "collect_date",
    {
        data_type     => "timestamp without time zone",
        default_value => undef,
        is_nullable   => 0,
        size          => 8,
    },
    "story_texts_id",
    { data_type => "integer", default_value => undef, is_nullable => 1, size => 4 },
);
__PACKAGE__->set_primary_key("stories_id");
__PACKAGE__->add_unique_constraint( "stories_story_text", ["story_texts_id"] );
__PACKAGE__->add_unique_constraint( "stories_guid",       ["guid"] );
__PACKAGE__->add_unique_constraint( "stories_pkey",       ["stories_id"] );
__PACKAGE__->has_many( "downloads", "MediaWords::DB::Downloads", { "foreign.stories_id" => "self.stories_id" }, );
__PACKAGE__->has_many(
    "feeds_stories_maps",
    "MediaWords::DB::FeedsStoriesMap",
    { "foreign.stories_id" => "self.stories_id" },
);
__PACKAGE__->belongs_to( "story_texts_id", "MediaWords::DB::StoryTexts", { story_texts_id => "story_texts_id" }, );
__PACKAGE__->belongs_to( "media_id",       "MediaWords::DB::Media",      { media_id       => "media_id" }, );
__PACKAGE__->has_many(
    "stories_tags_maps",
    "MediaWords::DB::StoriesTagsMap",
    { "foreign.stories_id" => "self.stories_id" },
);

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:svVxEJTC8rcmLrWVQh0ICg

#__PACKAGE__->many_to_many('feeds' => 'feeds_stories_map', 'feeds_id');

use MediaWords::DBI::Stories;

#TODO removed unused function
# # return the concatenated text of all downloads belonging to the story
# sub get_extracted_text
# {
#     my ($self) = @_;

#     my $db = DBIx::Simple->new( $self->result_source->storage->dbh );

#     return MediaWords::DBI::Stories::get_extracted_text( $db, { $self->get_columns } );
# }

# run MediaWords::Crawler::Extractor against the story downloads
sub extract_html
{
    my ($self) = @_;

    my $db = DBIx::Simple->new( $self->result_source->storage->dbh );

    return MediaWords::DBI::Stories::extract_html( $db, { $self->get_columns } );
}

# get the text of the story by looking first in story_texts, second in extracted_lines, and third by running MediaWords::Extractor
sub get_text
{
    my ($self) = @_;

    my $db = DBIx::Simple->new( $self->result_source->storage->dbh );

    return MediaWords::DBI::Stories::get_text( $db, { $self->get_columns } );
}

# You can replace this text with custom content, and it will be preserved on regeneration
1;

