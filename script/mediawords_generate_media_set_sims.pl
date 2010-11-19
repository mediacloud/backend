#!/usr/bin/perl

# generate similarity scores between one media set and each subsequent media set
#
# usage: mediawords_generate_media_set_sims.pl <week date> <media set> [<media set 1> ...]

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use PDL;

use MediaWords::DB;

# get word vectors for the top 500 words for each media set
sub get_media_set_vectors
{
    my ( $db, $media_set_ids, $date ) = @_;
    
    my $word_hash;
    my $media_set_vectors;
    
    for my $media_set_id ( @{ $media_set_ids } )
    {
        my $media_set = $db->find_by_id( "media_sets", $media_set_id ) || die ( "invalid media set $media_set_id" );

        my $words = $db->query( 
            "select ms.name, w.stem, w.stem_count::float / tw.total_count::float as stem_count " .
            "  from media_sets ms, top_500_weekly_words w, total_top_500_weekly_words tw " .
            "  where ms.media_sets_id = w.media_sets_id and ms.media_sets_id = ? and " .
            "    w.publish_week = date_trunc( 'week', ?::date ) and " .
            "    w.media_sets_id = tw.media_sets_id ",
            $media_set_id, $date )->hashes;
        
        for my $word ( @{ $words } )
        {
            $word_hash->{ $word->{ stem }  } ||= scalar( values( %{ $word_hash } ) );
            my $word_index = $word_hash->{ $word->{ stem } };
            
            $media_set->{ vector }->[ $word_index ] = $word->{ stem_count };
        }

        push( @{ $media_set_vectors }, $media_set );
    }    
    
    return $media_set_vectors;
}

# add the cosine similarity scores between the first media_set and each subsequent media set
sub add_cos_similarities
{
    my ( $media_sets ) = @_;

    my $num_words = scalar( @{ $media_sets->[ @{ $media_sets } - 1 ]->{ vector } } );

    for my $media_set ( @{ $media_sets } )
    {
        $media_set->{ pdl_vector } = zeroes $num_words;
        
        for ( my $i = 0; $i < $num_words; $i++ ) 
        {        
            index( $media_set->{ pdl_vector }, $i ) .= $media_set->{ vector }->[ $i ];
        }
    }
    
    my $n_base_vector = norm $media_sets->[ 0 ]->{ pdl_vector };
    
    for ( my $i = 1; $i < @{ $media_sets }; $i++ )
    {
        my $n_vector = norm $media_sets->[ $i ]->{ pdl_vector };
        $media_sets->[ $i ]->{ cos } = inner( $n_base_vector, $n_vector )->sclr();
    }
    
    return $media_sets;
}

sub main
{
    my $date = shift( @ARGV );
    my $media_set_ids = [ @ARGV ];
    
    if ( !$date || !$media_set_ids )
    {
        die( "usage: mediawords_generate_media_set_sims.pl <week date> <media set> [<media set 1> ...]" );
    }
    
    my $db = MediaWords::DB::connect_to_db;
    
    my $media_set_vectors = get_media_set_vectors( $db, $media_set_ids, $date );
    
    add_cos_similarities( $media_set_vectors );
    
    #print Dumper( $media_set_vectors );
    
    map { print "$_->{ name }:$_->{ cos }\n" } @{ $media_set_vectors };
}

main();