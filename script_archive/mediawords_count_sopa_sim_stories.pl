#!/usr/bin/env perl

# generate similarity matrix of all stories in sopa_stories.  count how many stories are above 
# SIMILARITY_THRESHOLD for each story that are after that story's publish date.  as a crude 
# form of clustering, find the single story with the highest sim stories count, then eliminate 
# all counted stories from consideration, then repeat, so that each story is only included in the 
# sim stories count of one story.

# usage: mediawords_count_sopa_sim_stories.pl [ --generate ] [ --start <date> ] [ --end <date> ]
#
# -g option makes the script regenerate the stories similarity matrix.  otherwise, the script
# uses cached similarities in the story_similarities table

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Util::CSV;

use Getopt::Long;

# threshold above which to count stories as similar
use constant SIMILARITY_THRESHOLD => 0.50;

# multiply similarity by this to turn it into an integer
use constant SIMILARITY_SCALE => 1000000;

# max number of most similar stories to find
use constant NUM_STORY_COUNTS => 100;

sub get_date_clauses
{
    my ( $prefix, $start, $end ) = @_;
    
    my $date_clause_list = [];
    
    push( @{ $date_clause_list }, "$prefix.publish_date >= '$start'::date" ) if ( $start );
    push( @{ $date_clause_list }, "$prefix.publish_date <= '$end'::date" ) if ( $end );
    
    return join( " ", map { "and $_" } @{ $date_clause_list } );
}

sub get_sopa_stories
{
    my ( $db, $start, $end ) = @_;
    
    my $date_clause = get_date_clauses( 's', $start, $end );
    
    return $db->query( 
        "select distinct s.*, m.name as media_name from stories s, sopa_stories ss, media m " .
        "  where s.stories_id = ss.stories_id and s.media_id = m.media_id $date_clause" )->hashes;
}

# apply inverse document frequency weighting to the word vector of each story
sub apply_idf_to_word_vectors
{
    my ( $stories ) = @_;
    
    my $length = 0;
    map { $length = ( $length > @{ $_->{ vector } } ) ? $length : @{ $_->{ vector } } } @{ $stories };
    
    for ( my $i = 0; $i < $length; $i++ )
    {
        print STDERR "apply_idf_to_word_vectors: word $i / $length\n" unless ( $i % 100 );
        my $document_count = 0;
        map { $document_count++ if ( $_->{ vector }->[ $i ] ) } @{ $stories };
        map { $_->{ vector }->[ $i ] /= $document_count if ( $_->{ vector }->[ $i ] ) } @{ $stories };
    }
}

# generate the big similarity matrix
sub generate_similarities
{
    my ( $db, $stories ) = @_;
    
    MediaWords::DBI::Stories::add_word_vectors( $db, $stories, 0, 1000, 'tiny' );
    
    # apply_idf_to_word_vectors( $stories );
    
    MediaWords::DBI::Stories::add_cos_similarities( $db, $stories );
    
    $db->query( "delete from story_similarities" );
    
    my $n = 1;
    for my $story ( @{ $stories } )
    {
        print STDERR "store: " . $n++ . " / " . scalar( @{ $stories } ) . " ...\n";
        $db->dbh->do( "copy story_similarities( stories_id_a, publish_day_a, stories_id_b, publish_day_b, similarity ) from STDIN" );

        for ( my $i; $i < @{ $story->{ similarities } }; $i++ )
        {
            my $story_b = $stories->[ $i ];
            next if ( $story_b->{ stories_id } >= $story->{ stories_id } );
            
            my $sim = $story->{ similarities }->[ $i ];
            next if ( !$sim );
            
            my $put = join( "\t", $story->{ stories_id }, $story->{ publish_date }, 
                $story_b->{ stories_id }, $story_b->{ publish_date }, int( $sim * SIMILARITY_SCALE ) );

            $db->dbh->pg_putcopydata( $put . "\n" );
        }

        $db->dbh->pg_putcopyend();
    }
}

# get the NUM_STORY_COUNTS stories with the highest similar stories counts
sub get_most_similar_stories
{
    my ( $db, $stories, $start, $end ) = @_;
    
    print STDERR "count " . scalar( @{ $stories } ) . " stories: ";
    
    my $date_clause = get_date_clauses( 's_a', $start, $end ) . ' ' . get_date_clauses( 's_b', $start, $end );
    
    my $n = 1;
    my $story_sim_counts = {};
    for my $story ( @{ $stories } )
    {
        print STDERR "." unless ( $n++ % 100 );
        my $count_a = $db->query( 
            "select count(*) from ( " . 
            "  select distinct ss.stories_id_b from story_similarities ss, stories s_a, stories s_b " . 
            "    where s_a.stories_id <> s_b.stories_id and s_a.stories_id = ss.stories_id_a and " .
            "      s_b.stories_id = ss.stories_id_b and s_a.media_id <> s_b.media_id and " .
            "      ss.stories_id_a = ? and ss.similarity > ? and ss.publish_day_a <= ss.publish_day_b $date_clause ) q",
            $story->{ stories_id }, SIMILARITY_THRESHOLD * SIMILARITY_SCALE )->list;
        my $count_b = $db->query( 
            "select count(*) from ( " . 
            "  select distinct ss.stories_id_a from story_similarities ss, stories s_a, stories s_b " . 
            "    where s_a.stories_id <> s_b.stories_id and s_a.stories_id = ss.stories_id_a and " .
            "      s_b.stories_id = ss.stories_id_b and s_a.media_id <> s_b.media_id and " .
            "      ss.stories_id_b = ? and ss.similarity > ? and ss.publish_day_b <= ss.publish_day_a $date_clause ) q",
            $story->{ stories_id }, SIMILARITY_THRESHOLD * SIMILARITY_SCALE )->list;
        my $count = $count_a + $count_b;
        
        $story_sim_counts->{ $story->{ stories_id } } =
            { count => $count, story => $story };
    }
    print STDERR "\n";
    
    my $most_similar_stories = [];
    for ( my $i = 0; ( $i < NUM_STORY_COUNTS ) && %{ $story_sim_counts }; $i++ )
    {
        my $max_count = 0;
        my $max_count_stories_id = 0;
        while ( my ( $stories_id, $story_count ) = each ( %{ $story_sim_counts } ) )
        {
            if ( $story_count->{ count } > $max_count )
            {
                $max_count = $story_count->{ count };
                $max_count_stories_id = $stories_id;
            }
        }
        
        last unless ( $max_count );
        
        my $max_story = $story_sim_counts->{ $max_count_stories_id }->{ story };
        print STDERR "$max_story->{ title }\n";
        my @sim_stories_ids_a = $db->query( 
            "  select distinct ss.stories_id_b from story_similarities ss, stories s_a, stories s_b " . 
            "    where s_a.stories_id <> s_b.stories_id and s_a.stories_id = ss.stories_id_a and s_b.stories_id = ss.stories_id_b and " .
            "      s_a.media_id <> s_b.media_id and " .
            "      ss.stories_id_a = ? and ss.similarity > ? and ss.publish_day_a <= ss.publish_day_b $date_clause ",
            $max_count_stories_id, SIMILARITY_THRESHOLD * SIMILARITY_SCALE )->flat;
        my @sim_stories_ids_b = $db->query( 
            "  select distinct ss.stories_id_a from story_similarities ss, stories s_a, stories s_b " . 
            "    where s_a.stories_id <> s_b.stories_id and s_a.stories_id = ss.stories_id_a and " .
            "      s_b.stories_id = ss.stories_id_b and s_a.media_id <> s_b.media_id and " .
            "      ss.stories_id_b = ? and ss.similarity > ? and ss.publish_day_b <= ss.publish_day_a $date_clause ",
            $max_count_stories_id, SIMILARITY_THRESHOLD * SIMILARITY_SCALE )->flat;
        my $sim_stories = [ map { $story_sim_counts->{ $_ }->{ story } } ( @sim_stories_ids_a, @sim_stories_ids_b ) ];
            
        push( @{ $most_similar_stories }, 
                { story => $max_story,
                  count => $max_count,
                  sim_stories => $sim_stories } );
                
        delete( $story_sim_counts->{ $max_count_stories_id } );
        for my $sim_stories_id ( @sim_stories_ids_a, @sim_stories_ids_b )
        {
            delete( $story_sim_counts->{ $sim_stories_id } );
        }

    }
    
    return $most_similar_stories;    
}

# print similar stories as a csv
sub print_similar_stories_csv
{
    my ( $similar_stories, $start, $end ) = @_;
    
    my $similar_stories_hashes = [];
    for my $similar_story ( @{ $similar_stories } )
    {
        my $story = $similar_story->{ story };
        push( @{ $similar_stories_hashes }, 
            { first_stories_id => $story->{ stories_id },
              sim_count => $similar_story->{ count },
              stories_id => $story->{ stories_id }, 
              title => $story->{ title }, 
              url => $story->{ url }, 
              publish_date => $story->{ publish_date },
              media_id => $story->{ media_id },
              media_name => $story->{ media_name } } );
    
        print STDERR "$similar_story->{ count }: [ $story->{ stories_id } ] $story->{ title } ( $story->{ media_name } : $story->{ publish_date } )\n";
        for my $s ( grep { $_->{ stories_id } } @{ $similar_story->{ sim_stories } } )
        {
            if ( $s && $s->{ stories_id } ) { 
                push( @{ $similar_stories_hashes }, 
                    { first_stories_id => $story->{ stories_id },
                      sim_count => $similar_story->{ count },
                      stories_id => $s->{ stories_id }, 
                      title => $s->{ title }, 
                      url => $s->{ url }, 
                      publish_date => $s->{ publish_date },
                      media_id => $s->{ media_id },
                      media_name => $s->{ media_name } } );
                #print STDERR "\t[ $s->{ stories_id } ] $s->{ title } ( $s->{ media_name } : $s->{ publish_date } )\n";
            }
        }
    }
    
    my $encoded_csv = MediaWords::Util::CSV::get_hashes_as_encoded_csv(
        $similar_stories_hashes, [ qw(first_stories_id sim_count stories_id title url publish_date media_id media_name) ] );
    
    my $csv_file_name = 'sopa_sim_counts';
    $csv_file_name .= "_s_$start" if ( $start );
    $csv_file_name .= "_e_$end" if ( $end );
    $csv_file_name .= '.csv';
    
    die( "'$csv_file_name' already exists" ) if ( -f $csv_file_name );
    open( FILE, ">$csv_file_name" ) || die( "Unable to open file '$csv_file_name': $!" );
    
    print FILE $encoded_csv;
    
    close( FILE );
}

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    
    my $db = MediaWords::DB::connect_to_db;
    
    my ( $generate, $start, $end );
    GetOptions(
        "start=s" => \$start,
        "end=s" => \$end,
        "generate!" => \$generate ) || return;
        
    if ( $generate && ( $start || $end ) )
    {
        die( "Cannot specify --generate with either --start or --end" );
    }
    
    my $stories = get_sopa_stories( $db, $start, $end );
    
    if ( $generate )
    {
        generate_similarities( $db, $stories );
    }    
    
    my $similar_stories = get_most_similar_stories( $db, $stories, $start, $end );
    
    print_similar_stories_csv( $similar_stories, $start, $end );
}

main();