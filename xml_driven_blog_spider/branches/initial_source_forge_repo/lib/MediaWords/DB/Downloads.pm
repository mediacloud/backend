package MediaWords::DB::Downloads;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("downloads");
__PACKAGE__->add_columns(
    "downloads_id",
    {
        data_type     => "integer",
        default_value => "nextval('downloads_downloads_id_seq'::regclass)",
        is_nullable   => 0,
        size          => 4,
    },
    "feeds_id",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
    "stories_id",
    { data_type => "integer", default_value => undef, is_nullable => 1, size => 4 },
    "parent",
    { data_type => "integer", default_value => undef, is_nullable => 1, size => 4 },
    "url",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 1024,
    },
    "host",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 1024,
    },
    "download_time",
    {
        data_type     => "timestamp without time zone",
        default_value => undef,
        is_nullable   => 0,
        size          => 8,
    },
    "type",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 32,
    },
    "state",
    {
        data_type     => "character varying",
        default_value => undef,
        is_nullable   => 0,
        size          => 32,
    },
    "path",
    {
        data_type     => "text",
        default_value => undef,
        is_nullable   => 1,
        size          => undef,
    },
    "error_message",
    {
        data_type     => "text",
        default_value => undef,
        is_nullable   => 1,
        size          => undef,
    },
    "priority",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
    "sequence",
    { data_type => "integer", default_value => undef, is_nullable => 0, size => 4 },
    "extracted",
    { data_type => "boolean", default_value => undef, is_nullable => 1, size => 1 },
);
__PACKAGE__->set_primary_key("downloads_id");
__PACKAGE__->add_unique_constraint( "downloads_pkey", ["downloads_id"] );
__PACKAGE__->belongs_to( "stories_id", "MediaWords::DB::Stories",   { stories_id   => "stories_id" }, );
__PACKAGE__->belongs_to( "feeds_id",   "MediaWords::DB::Feeds",     { feeds_id     => "feeds_id" }, );
__PACKAGE__->belongs_to( "parent",     "MediaWords::DB::Downloads", { downloads_id => "parent" }, );
__PACKAGE__->has_many( "downloads", "MediaWords::DB::Downloads", { "foreign.parent" => "self.downloads_id" }, );
__PACKAGE__->has_many(
    "extracted_lines",
    "MediaWords::DB::ExtractedLines",
    { "foreign.downloads_id" => "self.downloads_id" },
);
__PACKAGE__->has_many(
    "extractor_training_lines",
    "MediaWords::DB::ExtractorTrainingLines",
    { "foreign.downloads_id" => "self.downloads_id" },
);

# Created by DBIx::Class::Schema::Loader v0.04005 @ 2008-09-22 23:19:53
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:fdYlsAoE65xfOAnpR6zN+A

use DBIx::Simple;
use File::Path;
use HTML::Strip;
use HTTP::Request;
use IO::Uncompress::Gunzip;
use LWP::UserAgent;

use MediaWords::Crawler::Extractor;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;

# fetch the content for the given download as a content_ref
sub fetch_content
{
    my ($self) = @_;

    return MediaWords::DBI::Downloads::fetch_content( { $self->get_columns } );
}

# fetch the content as lines in an array
sub fetch_preprocessed_content_lines
{
    my ($self) = @_;

    return MediaWords::DBI::Downloads::fetch_preprocessed_content_lines( { $self->get_columns } );
}

# return the extracted text for the given download
sub get_previously_extracted_text
{
    my ($self) = @_;

    my $db = DBIx::Simple->new( $self->result_source->storage->dbh );

    return MediaWords::DBI::Downloads::get_extracted_text( $db, { $self->get_columns } );
}

# run MediaWords::Crawler::Extractor against the download content
sub extract_html
{
    my ($self) = @_;

    my $db = DBIx::Simple->new( $self->result_source->storage->dbh );

    return MediaWords::DBI::Downloads::extract_html( $db, { $self->get_columns } );
}

# store the download content in the file system
sub store_content
{
    my ( $self, $content_ref ) = @_;

    my $db = DBIx::Simple->new( $self->result_source->storage->dbh );

    MediaWords::DBI::Downloads::store_content( $db, { $self->get_columns }, $content_ref );
}

# You can replace this text with custom content, and it will be preserved on regeneration
1;
