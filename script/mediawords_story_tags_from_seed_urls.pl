#!/usr/bin/env perl

# given a csv file of seed urls for a given controversy that also contains media types,
# import those media types as story tags

# usage: $0 <csv file> <tag set name > [ <category map csv> ]
# * csv file - file of seeds urls with url and media_type fields
# * tag set name - tag set used for story tags
# * category map csv - optional csv that maps multiple different categories
#   into single categories, useful for normalizing categories. format is
#   comma separate lines, with the first entry in each line the destination
#   category and subsequent entries on the line the source categories

use strict;
use warnings;

BEGIN
{
    $ENV{ MEDIACLOUD_IGNORE_DB_SCHEMA_VERSION } = 1;
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Text::CSV_XS;

use MediaWords::DB;
use MediaWords::Util::CSV;
use MediaWords::Util::Tags;

# given a csv file in the format described in the category map description at the top of this file,
# create a hash of source categories to destination categories
sub get_media_type_map
{
    my ( $csv_file ) = @_;

    return unless ( $csv_file );

    my $csv = Text::CSV_XS->new();
    open my $fh, "<:encoding(utf8)", $csv_file || die( "Unable to open file '$csv_file': $!" );

    my $media_type_map = {};
    while ( my $line = $csv->getline( $fh ) )
    {
        my $dest = $line->[ 0 ];
        map { $media_type_map->{ $_ } = $dest } @{ $line };
    }

    close( $fh );

    return $media_type_map;
}

# given a csv record, add a tag for the 'Media type'
sub add_url_type_as_story_tag
{
    my ( $db, $tag_set_name, $url_type, $media_type_map ) = @_;

    my $url = $url_type->{ url };
    if ( !$url )
    {
        warn( "no url" );
        return;
    }

    my $media_type = $url_type->{ 'media_type' };

    $media_type = lc( $media_type );
    $media_type =~ s/\(.*\)//;
    $media_type =~ s/\s+/ /;
    $media_type =~ s/^\s+//;
    $media_type =~ s/\s+$//;

    return if ( !$media_type || $media_type =~ /^\?+$/ );

    if ( $media_type_map )
    {
        my $mapped_media_type = $media_type_map->{ $media_type }
          || warn( "media type '$media_type' not found in media type map" );

        $media_type = $mapped_media_type;
    }

    return if ( !$media_type || ( $media_type eq 'ignore' ) );

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
    my ( $file, $tag_set_name, $media_type_map_csv ) = @ARGV;

    die( "usage: $0 <csv file> <tag set name > [ <category map csv> ]" ) unless ( $file && $tag_set_name );

    print STDERR "$0: $file\n";

    my $db = MediaWords::DB::connect_to_db;

    my $url_types = MediaWords::Util::CSV::get_csv_as_hashes( $file, 1 );

    my $media_type_map = get_media_type_map( $media_type_map_csv );

    my $i = 0;
    map { print STDERR $i++ . "\n"; add_url_type_as_story_tag( $db, $tag_set_name, $_, $media_type_map ) } @{ $url_types };
}

main();
