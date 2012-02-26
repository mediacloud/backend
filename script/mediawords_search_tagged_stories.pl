#!/usr/bin/perl

# search through a set of tagged stories for a set of keywords.  for each 
# matching keyword, add the corresponding tag

# usage: mediawords_search_tagged_stories.pl <tag_set:tag>

# tags an input file on stdin in the following format
# tag_set:tag regex
# tag_set:tag regex

# the searching is done in the 

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::Util::Tags;

sub get_patterns_from_input
{
    my ( $db ) = @_;
    
    my $patterns = [];
    
    while ( my $line = <STDIN> )
    {
        chomp( $line );
        
        my ( $tag_string, $regex ) = split( /\s+/, $line, 2 );
        
        die( "Unable to parse input line: '$line'" ) if ( !$tag_string || !$regex );
        
        my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $db, $tag_string );
        
        push( @{ $patterns}, { tag => $tag, regex => $regex } );
    }
    
    return $patterns;
}

# construct the regex, run it against the db, and return a list of which patterns each
# story matches
sub search_and_tag_stories
{
    my ( $db, $tag, $patterns ) = @_;
    
    my $match_columns = [];
    for ( my $i = 0; $i < @{ $patterns }; $i++ )
    {
        my $pattern = $patterns->[ $i ];
        # gotta do this weird sub-sub-query to get the planner not to seq scan story_sentences
        my $clause = "( s.title ~* '$pattern->{ regex }' or s.description ~* '$pattern->{ regex }' or " . 
            "exists ( select 1 " . 
            "         from ( select * from story_sentences ssa_$i where s.stories_id = ssa_$i.stories_id ) as ss_$i " . 
            "         where ss_$i.sentence ~* '$pattern->{ regex }' ) ) match_$i";
        push( @{ $match_columns }, $clause );
    }

    my $match_columns_list = join( ", ", @{ $match_columns } );

    my $story_matches = $db->query( 
        "select s.stories_id, s.title, $match_columns_list from stories s, stories_tags_map stm " .
        "  where s.stories_id = stm.stories_id and stm.tags_id = ?", 
        $tag->{ tags_id } )->hashes;
    
    print @{ $story_matches } . " stories\n";
    for ( my $i = 0; $i < @{ $patterns }; $i++ )
    {
        print "$patterns->[ $i ]->{ tag }->{ tag }: " . scalar( grep { $_->{ "match_$i" } } @{ $story_matches } ) . "\n";
    }

    $db->{ dbh }->{ AutoCommit } = 0;
    my $c = 0;
    for my $story_match ( @{ $story_matches } )
    {
        print STDERR "update story $story_match->{ title }\n";
        for ( my $i = 0; $i < @{ $patterns }; $i++ )
        {
            my $pattern = $patterns->[ $i ];
            $db->query( 
                "delete from stories_tags_map where stories_id = ? and tags_id = ?", 
                $story_match->{ stories_id }, $pattern->{ tag }->{ tags_id } );
            if ( $story_match->{ "match_$i" } ) 
            {
                print STDERR "$pattern->{ tag }->{ tag }\n";
                $db->query(
                    "insert into stories_tags_map ( stories_id, tags_id ) values ( ?, ? )",
                    $story_match->{ stories_id }, $pattern->{ tag }->{ tags_id } );
            }
        }
        
        $db->commit if ( !( $c % 100)  )
    }
}

sub main
{
    my ( $tag_string ) = @ARGV;
    
    die( "usage: $0 <tag_set:tag>" ) if ( !$tag_string );
    
    my $db = MediaWords::DB::connect_to_db;
    
    my ( $tag ) = MediaWords::Util::Tags::lookup_tag( $db, $tag_string ) || die( "unknown tag: $tag_string" );
    
    my $patterns = get_patterns_from_input( $db );
    
    die( "no patterns found in input" ) if ( !@{ $patterns } );
    
    search_and_tag_stories( $db, $tag, $patterns );
}

main();