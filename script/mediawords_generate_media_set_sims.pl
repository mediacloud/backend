#!/usr/bin/perl

# generate similarity scores between one media set and each subsequent media set
#
# usage: mediawords_generate_media_set_sims.pl <dashbaord_topics_id | 'null'> <week date> [<media set 1> <media set 2> ...]

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use List::Util;
use MediaWords::DB;
use PDL;

# get word vectors for the top 500 words for each media set
sub get_media_set_vectors
{
    my ( $db, $media_set_ids, $dashboard_topics_id, $date ) = @_;
    
    my $word_hash;
    my $media_set_vectors;
    
    for my $media_set_id ( @{ $media_set_ids } )
    {
        my $media_set = $db->find_by_id( "media_sets", $media_set_id ) || die ( "invalid media set $media_set_id" );
        print STDERR "querying vectors for $media_set->{ name }\n";

        my $dashboard_topic_clause;
        if ( $dashboard_topics_id eq 'null' ) 
        {
            $dashboard_topic_clause = 'w.dashboard_topics_id is null and tw.dashboard_topics_id is null';
        }
        else {
            $dashboard_topics_id += 0;
            $dashboard_topic_clause = "w.dashboard_topics_id = $dashboard_topics_id and tw.dashboard_topics_id = $dashboard_topics_id";
        }

        my $words = $db->query( 
            "select ms.name, w.stem, w.stem_count::float / tw.total_count::float as stem_count " .
            "  from media_sets ms, top_500_weekly_words w, total_top_500_weekly_words tw " .
            "  where ms.media_sets_id = w.media_sets_id and ms.media_sets_id = ? and " .
            "    w.publish_week = date_trunc( 'week', ?::date ) and " .
            "    w.media_sets_id = tw.media_sets_id and $dashboard_topic_clause",
            $media_set_id, $date )->hashes;
        
        $media_set->{ vector } = [ 0 ];
        
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

    my $num_words = List::Util::max ( map { scalar( @{ $_->{ vector } } ) } @{ $media_sets } ) - 1;
    
    print STDERR "num_words: $num_words\n";

    for my $media_set ( @{ $media_sets } )
    {
        $media_set->{ pdl_vector } = zeroes $num_words;
        
        for ( my $i = 0; $i < $num_words; $i++ ) 
        {        
            index( $media_set->{ pdl_vector }, $i ) .= $media_set->{ vector }->[ $i ];
        }
    }
        
    for ( my $i = 0; $i < @{ $media_sets }; $i++ )
    {        
        $media_sets->[ $i ]->{ cos }->[ $i ] = 1;

        for ( my $j = $i + 1; $j < @{ $media_sets }; $j++ )
        {
            print STDERR "computing similarity for $media_sets->[ $i ]->{name} and $media_sets->[ $j ]->{ name }\n";
            my $n_i = norm $media_sets->[ $i ]->{ pdl_vector };
            my $n_j = norm $media_sets->[ $j ]->{ pdl_vector };
            my $sim = inner( $n_i, $n_j )->sclr;
            
            $media_sets->[ $i ]->{ cos }->[ $j ] = $sim;
            $media_sets->[ $j ]->{ cos }->[ $i ] = $sim;
        }
    }
    
    return $media_sets;
}

sub main
{
    my $dashboard_topics_id = shift( @ARGV );
    my $date = shift( @ARGV );
    my $media_set_ids = [ @ARGV ];
    
    if ( !$dashboard_topics_id || !$date || !$media_set_ids )
    {
        die( "usage: mediawords_generate_media_set_sims.pl <dashbaord_topics_id | 'null'> <week date> [<media set 1> <media set 2> ...]" );
    }
    
    my $db = MediaWords::DB::connect_to_db;
    
    my $media_set_vectors = get_media_set_vectors( $db, $media_set_ids, $dashboard_topics_id, $date );
    
    add_cos_similarities( $media_set_vectors );
    
    #print Dumper( $media_set_vectors );
    
    print "," . join( ",", map { '"'. $_->{ name } .'"' } @{ $media_set_vectors } ) . "\n";
    
    for my $msv ( @{ $media_set_vectors } )
    {
        print '"' . $msv->{ name }. '",' . join( ",", @{ $msv->{ cos } } ) . "\n";
    }

}

main();