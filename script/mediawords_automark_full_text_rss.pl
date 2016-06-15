#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Encode;
use MediaWords::DB;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use DBIx::Simple::MediaWords;
use MediaWords::DBI::Downloads;
use List::Uniq ':all';

sub get_media_ids_to_update_by_rss_length_and_similarity
{
    my ( $dbs ) = @_;

    my $avg_similarity = 0.97;
    my $avg_rss_length = 1000;

    my @media_ids_to_update;

    while ( $avg_rss_length <= 10000 )
    {

        die unless $avg_similarity > 0;

        my @new_media_ids_to_update = $dbs->query(
'select media.media_id from media_rss_full_text_detection_data natural join media where  avg_similarity >= ? and avg_rss_length > ? and full_text_rss is null',
            $avg_similarity, $avg_rss_length
        )->flat;

        push @media_ids_to_update, @new_media_ids_to_update;

        @media_ids_to_update = uniq( @media_ids_to_update );

        $avg_rss_length += 1000;
        $avg_similarity -= 0.01;
    }

    @media_ids_to_update = uniq( @media_ids_to_update );

    return \@media_ids_to_update;
}

sub set_media_ids_to_full_text_rss
{
    my ( $dbs, $media_ids_to_update, $reason ) = @_;

    say "Updating " . scalar( @$media_ids_to_update ) . " media based on $reason";

    if ( scalar( @$media_ids_to_update ) > 0 )
    {
        $dbs->query( "update media set full_text_rss = true where full_text_rss is null and media_id in (??)",
            @$media_ids_to_update );
    }

    return;
}

sub update_media_ids_from_query
{
    my ( $dbs, $query ) = @_;

    my @media_ids_to_update = $dbs->query( $query )->flat;

    set_media_ids_to_full_text_rss( $dbs, \@media_ids_to_update, $query );
}

sub main
{

    my $dbs = MediaWords::DB::connect_to_db;

    say "Finding media ids to update by similarity and length";

    my $media_ids_to_update = get_media_ids_to_update_by_rss_length_and_similarity( $dbs );

    say "initially updating " . scalar( @{ $media_ids_to_update } ) . " media ids:";

    say join ",", @{ $media_ids_to_update };

    if ( scalar( @{ $media_ids_to_update } ) > 0 )
    {

        $dbs->query( 'update media set full_text_rss = true where media_id in (??)', @{ $media_ids_to_update } ) || die;

    }
    my @media_ids_to_update = $dbs->query(
'select media_id from (select media_id, avg_rss_length, avg_extracted_length, (abs(avg_rss_length-avg_extracted_length)/avg_rss_length) as length_proportion  from media_rss_full_text_detection_data where avg_rss_length > 400 ) as foo where length_proportion < 0.03'
    )->flat;

    say
"Running: update media set full_text_rss = true where full_text_rss is null and url like '\%livejournal\%' and media_id in (??)";
    $dbs->query(
"update media set full_text_rss = true where full_text_rss is null and url like '\%livejournal\%' and media_id in (??)",
        @media_ids_to_update
    );

    update_media_ids_from_query( $dbs,
"select media_id from media_rss_full_text_detection_data natural join media where avg_similarity >= 0.95 and min_similarity >= 0.80 and (url like '%blogspot%' or url like '%livejournal%' or url like '%liveinternet.ru%' or url like '%blogs.mail.ru%' or url like '%diary.ru%' ) and full_text_rss is null "
    );

    update_media_ids_from_query( $dbs,
"select media_id from media_rss_full_text_detection_data natural join media where avg_similarity >= 0.99 and full_text_rss is null "
    );

    update_media_ids_from_query( $dbs,
"select media_id from media_rss_full_text_detection_data natural join media where avg_rss_length >= 6000 and full_text_rss is null "
    );

    update_media_ids_from_query( $dbs,
"select media_id from media_rss_full_text_detection_data natural join media where avg_rss_discription >= 400 and avg_extracted_length <= 0 and full_text_rss is null"
    );

}

main();
