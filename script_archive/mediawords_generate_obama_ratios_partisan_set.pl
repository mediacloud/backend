#!/usr/bin/env perl

# generate csv of otal number of obama and romney mentions for
# right, left, and center blogs

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;

use MediaWords::DB;
use MediaWords::Solr;
use MediaWords::Util::CSV;
use MediaWords::Util::Tags;

# query solr to return the number of sentences matching 'obama' and 'romney',
# and the obama:romney ratio for the medium
sub get_obama_romney_medium_counts
{
    my ( $db, $medium, $tag_name ) = @_;

    my $fq = [ "media_id:$medium->{ media_id }", "publish_date:[2012-10-01T00:00:00Z TO 2012-11-01T00:00:00Z]" ];

    my $obama_res = MediaWords::Solr::query( { fq => $fq, q => 'obama', rows => 0 } );
    $medium->{ obama } = $obama_res->{ response }->{ numFound };

    my $romney_res = MediaWords::Solr::query( { fq => $fq, q => 'romney', rows => 0 } );
    $medium->{ romney } = $romney_res->{ response }->{ numFound };

    my $o = $medium->{ obama }  || 1;
    my $r = $medium->{ romney } || 1;

    $medium->{ ratio } = $o / $r;

    $medium->{ tag_name } = $tag_name;

    print STDERR "$tag_name $medium->{ name }: o $medium->{ obama } : r $medium->{ romney } = $medium->{ ratio }\n";

    return $medium;
}

# for each media source associated with the given tag, return the number of sentences matching 'obama' and 'romney',
# and the obama:romney ratio
sub get_obama_romney_tag_counts
{
    my ( $db, $tag_name ) = @_;

    my $tag = MediaWords::Util::Tags::lookup_tag( $db, $tag_name ) || die( "Unable to find tag '$tag_name'" );

    my $media = $db->query( <<END, $tag->{ tags_id } )->hashes;
select m.* 
    from media m 
        join media_tags_map mtm on m.media_id = mtm.media_id
    where
        mtm.tags_id = ?
END

    my $counts = [];
    for my $medium ( @{ $media } )
    {
        my $medium_counts = get_obama_romney_medium_counts( $db, $medium, $tag_name );
        push( @{ $counts }, $medium_counts );
    }

    return $counts;
}

sub main
{
    my $db = MediaWords::DB::connect_to_db();

    my $tag_names = [ map { 'partisan_coding_20140217:' . $_ } qw(liberal conservative libertarian none) ];

    push( @{ $tag_names }, 'collection:ap_english_us_top25_20100110' );

    my $counts = [];
    for my $tag_name ( @{ $tag_names } )
    {
        my $tag_counts = get_obama_romney_tag_counts( $db, $tag_name );
        push( @{ $counts }, @{ $tag_counts } );
    }

    my $csv_fields = [ 'media_id', 'url', 'name', 'tag_name', 'obama', 'romney', 'ratio' ];
    print MediaWords::Util::CSV::get_hashes_as_encoded_csv( $counts, $csv_fields );
}

main();
