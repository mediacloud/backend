#!/usr/bin/env perl

# given a csv file of seed urls for a given controversy that also contains media types,
# import those media types as story tags

use strict;

BEGIN
{
    $ENV{ MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION } = 1;
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;
use MediaWords::Util::CSV;
use MediaWords::Util::Tags;

# given a csv record, add a tag for the 'Media type'
sub add_url_type_as_story_tag
{
    my ( $db, $tag_set_name, $url_type ) = @_;

    my $url = $url_type->{ url };
    if ( !$url )
    {
        warn( "no url" );
        return;
    }

    my $media_type = $url_type->{ 'media_type' };
    return unless ( $media_type );

    $media_type = lc( $media_type );
    $media_type =~ s/\(.*\)//;
    $media_type =~ s/\s+/ /;
    $media_type =~ s/^\s+//;
    $media_type =~ s/\s+$//;

    return if ( $media_type =~ /^\?+$/ );

    my $seed_url = $db->query( "select * from controversy_seed_urls where url = ?", $url )->hash;
    if ( !$seed_url )
    {
        warn( "No seed url found for '$url'" );
        return;
    }

    my $stories_id = $seed_url->{ stories_id };
    if ( !$stories_id )
    {
        warn( "No stories_id in seed url '$url'" );
        return;
    }

    my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, "$tag_set_name:$media_type" );

    print STDERR "$media_type: $url\n";

    my $tag_exists = $db->query( <<END, $stories_id, $tag->{ tags_id } )->hash;
select * from stories_tags_map where stories_id = ? and tags_id = ?
END
    return if ( $tag_exists );

    $db->query( <<END, $stories_id, $tag->{ tags_id } );
insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )
END

}

sub main
{
    my ( $file, $tag_set_name ) = @ARGV;

    die( "usage: $0 <csv file> <tag set name >" ) unless ( $file && $tag_set_name );

    my $db = MediaWords::DB::connect_to_db;

    my $url_types = MediaWords::Util::CSV::get_csv_as_hashes( $file, 1 );

    my $i = 0;
    map { print STDERR $i++ . "\n"; add_url_type_as_story_tag( $db, $tag_set_name, $_ ) } @{ $url_types };
}

main();
