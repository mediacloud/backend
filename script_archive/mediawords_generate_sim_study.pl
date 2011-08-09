#!/usr/bin/perl -w

# generate the story pairs for the similarity study

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::DBI::Stories;

use Text::CSV_XS;

# pull samples from the week following each of the below dates
use constant SAMPLE_DATES => ( '2011-04-18', '2011-01-17', '2010-10-18' );

# the range to use to sample the story pairs by similarity -- so a range of 0.25
# means that we will pull equal numbers of story pairs from those pairs that
# have similarities of 0 - 0.25, 0.25 - 0.5, 0.5 - 0.75, 0.75 - 1.0
use constant SAMPLE_RANGE => 0.25;

# number of pairs to pull from each sample range
use constant SAMPLE_RANGE_PAIRS => 6;

# get the set of stories belonging to study sets and feeds for the week following the given date
sub get_stories 
{
    my ( $db, $date ) = @_;

    my $blog_stories = $db->query( 
        "select s.* from stories s, media_tags_map mtm " . 
        "  where s.media_id = mtm.media_id and mtm.tags_id in ( 8875115, 8875114 ) " . 
        "    and date_trunc( 'day', s.publish_date ) between '$date' and now() + interval '6 days' " . 
        "  order by random() limit 1000" )->hashes; 

    my $msm_stories = $db->query( 
        "select s.* from stories s, feeds_stories_map fsm, " . 
        "    ( select min( stories_id ) min_stories_id from stories where publish_date = '$date'::date ) ms " . 
        "  where s.stories_id = fsm.stories_id and fsm.feeds_id in ( 390, 61 ) " . 
        "    and fsm.stories_id >= ms.min_stories_id " . 
        "    and date_trunc( 'day', s.publish_date ) between '$date' and now() + interval '6 days' " . 
        "  order by random() limit 1000" )->hashes; 

    my $limit = @{ $msm_stories } < 1000 ? @{ $msm_stories } : 1000;
    $limit = @{ $blog_stories } < $limit ? @{ $blog_stories } : $limit;
    
    splice( @{ $msm_stories }, $limit );
    splice( @{ $blog_stories }, $limit );
    
    return [ @{ $msm_stories }, @{ $blog_stories } ];
}

# given a list of stories with similarity scores included, produce a set of story pairs
# in the form { similarity => $s, $stories => [ $story_1, $story_2 ] }
sub get_story_pairs 
{
    my ( $stories ) = @_;
    
    my $story_pairs = [];
    
    for ( my $i = 1; $i < @{ $stories }; $i++ )
    {
        for ( my $j = 0; $j < $i; $j++ )
        {
            push( @{ $story_pairs }, {        
                similarity => $stories->[ $i ]->{ similarities }->[ $j ],
                stories => [ $stories->[ $i ], $stories->[ $j ] ] } );
        }
    }
    
    return [ sort { $a->{ similarity } <=> $b->{ similarity } } @{ $story_pairs } ];
}

# given a set of story pairs, return SAMPLE_RANGE_PAIRS pairs randomly selected
# from all pairs with a similarity between $floor and $floor + SAMPLE_RANGE.
# assume that the story pairs are sorted by similarity in ascending order
sub get_sample_pairs
{
    my ( $story_pairs, $floor ) = @_;
    
    my $start = 0;
    while ( $story_pairs->[ $start ] && ( $story_pairs->[ $start ]->{ similarity } < $floor ) )
	{
		$start++;
	}
	return [] if ( !$story_pairs->[ $start ] );

    my $end = $start;
    while ( $story_pairs->[ $end ] && ( $story_pairs->[ $end ]->{ similarity } < ( $floor + SAMPLE_RANGE ) ) ) 
	{
		$end++;
	}
	$end--;

	my $max_pairs = $end - $start;
	if ( ( $end - $start ) > SAMPLE_RANGE_PAIRS )
	{
		$max_pairs = SAMPLE_RANGE_PAIRS;
	}
	else {
    	warn( "Unable to find SAMPLE_RANGE_PAIRS pairs within range" );
	}

    my $range_pairs = [ @{ $story_pairs }[ $start .. $end ] ];
    $range_pairs = [ sort { int( rand( 3 ) ) - 1 } @{ $range_pairs } ];

    return [ @{ $range_pairs }[ 0 .. ( $max_pairs - 1 ) ] ];
}

# print the story pairs in csv format
sub print_story_pairs_csv
{
    my ( $story_pairs ) = @_;

    my $csv = Text::CSV_XS->new;
    
    $csv->combine( qw/similarity title_1 title_2 url_1 url_2 stories_id_1 stories_id_2 media_id_1 media_id2 publish_date_1 publish_date_2/ );
    my $output = $csv->string . "\n";

    for my $story_pair ( @{ $story_pairs } )
    {
        my $sim = $story_pair->{ similarity };
        my $stories = $story_pair->{ stories };
        $csv->combine( $sim, map { ( $stories->[ 0 ]->{ $_ }, $stories->[ 1 ]->{ $_ } ) } qw/title url stories_id media_id publish_date/ );
        $output .= $csv->string . "\n";
    }
    
    my $encoded_output = Encode::encode( 'utf-8', $output );
    
    print $encoded_output;   
}

sub main 
{
    my $db = MediaWords::DB::connect_to_db;
    
    my $study_story_pairs = [];
    
    for my $date ( SAMPLE_DATES )
    {
		print STDERR "$date: get_stories\n";
        my $stories = get_stories( $db, $date );            
        
		print STDERR "$date: add_sims\n";
        MediaWords::DBI::Stories::add_cos_similarities( $db, $stories );
        
		print STDERR "$date: get_story_pairs\n";
        my $all_story_pairs = get_story_pairs( $stories );
        
        for ( my $floor = 0; $floor < 1; $floor += SAMPLE_RANGE )
        {
			print STDERR "$date: $floor get_sample_pairs\n";
            my $sample_story_pairs = get_sample_pairs( $all_story_pairs, $floor );
            push( @{ $study_story_pairs }, @{ $sample_story_pairs } );
        }        
		print STDERR "$date: done\n";
    }

	print STDERR "print_story_pairs\n";
    print_story_pairs_csv( $study_story_pairs );
}

main();
