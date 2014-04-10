#!/usr/bin/env perl

# extract the text for the given story using the heuristic and crf extractors
use strict;

use Data::Dumper;
use Statistics::Basic;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;

sub get_extracted_text_for_story
{
    my ( $db, $story, $extractor_method ) = @_;
    
    my $downloads = $db->query( "select * from downloads where stories_id = ? order by downloads_id", $story->{ stories_id } )->hashes;

    my $config = MediaWords::Util::Config::get_config;

    $config->{ mediawords }->{ extractor_method } = $extractor_method;
    my $h_texts = [];
    for my $download ( @{ $downloads } )
    {
        my $res = MediaWords::DBI::Downloads::extractor_results_for_download( $db, $download );
        push( @{ $h_texts }, join( "\n", map { $res->{ download_lines }->[ $_ ] } @{ $res->{ included_line_numbers } } ) );        
        # print Dumper( $res->{ included_line_numbers } );

        # for ( my $i = 0; $i < @{ $res->{ scores } }; $i++ )
        # {
        #     print Dumper( $res->{ scores }->[ $i ] );
        #     print $res->{ download_lines }->[ $i ] . "\n";
        # }
    }
    
    print "extracted $story->{ url } [$extractor_method]\n";
    
    return join( "\n****\n", @{ $h_texts } );
}

sub get_extractor_stats
{
    my ( $db, $stories ) = @_;
    
    my ( $text_lengths, $mean_text_length, $sd_text_length, $num_short_stories );
    
    my $stats = {};
    for my $method ( 'HeuristicExtractor', 'CrfExtractor' )
    {
        my $texts = [];
        map { push( @{ $texts }, get_extracted_text_for_story( $db, $_, $method ) ) } @{ $stories };
        
        $stats->{ $method }->{ lengths } = [ map { length( $_ ) } @{ $texts } ];
        $stats->{ $method }->{ mean_length } = 0 + Statistics::Basic::mean( $stats->{ $method }->{ lengths } );
        $stats->{ $method }->{ sd_length } = 0 + Statistics::Basic::stddev( $stats->{ $method }->{ lengths } );
        $stats->{ $method }->{ num_short_stories } = scalar( grep { $_ < 128 } @{ $stats->{ $method }->{ lengths } } );
    }
    
    return $stats;
}

sub main
{
    $| = 1;
    
    my $db = MediaWords::DB::connect_to_db;

    my $stories = {};

    my $num_stories = 50;

    print "fetching spidered stories ...\n";
    $stories->{ spidered } = $db->query( <<END )->hashes;
select s.*
    from stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id )
        left join stories_tags_map stm on ( s.stories_id = stm.stories_id and stm.tags_id = 8875452 )
    where
        cs.controversies_id = 563 and
        stm.tags_id is not null
    order by ( s.stories_id % 1789 ) asc, stories_id
    limit $num_stories
END

    print "fetching unspidered stories ...\n";
    $stories->{ unspidered } = $db->query( <<END )->hashes;
select s.*
    from stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id )
        left join stories_tags_map stm on ( s.stories_id = stm.stories_id and stm.tags_id = 8875452 )
    where
        cs.controversies_id = 563 and
        stm.tags_id is null
    order by ( s.stories_id % 1789 ) asc, stories_id
    limit $num_stories
END

    print "fetching portuguese stories ...\n";
    $stories->{ portuguese } = $db->query( <<END )->hashes;
select s.*
    from stories s
        join media_tags_map mtm on ( s.media_id = mtm.media_id and mtm.tags_id = 8877968 )
        left join stories_tags_map stm on ( s.stories_id = stm.stories_id and stm.tags_id = 8875452 )
        join downloads d on ( d.stories_id = s.stories_id )
    where ( s.stories_id % 7 ) = 0 and
        d.state = 'success' and
        stm.tags_id is null
    order by s.stories_id desc
    limit $num_stories
END

    my $stats = {};
    for my $story_set ( keys( %{ $stories } ) )
    {        
        print "PROCESSING SET $story_set...\n";
        my $s = get_extractor_stats( $db, $stories->{ $story_set } );
        
        $stats->{ $story_set } = $s;
        
        print Dumper( $s );
        print "\n";
    }
    
    print Dumper( $stats );
    
    for my $story_set ( keys( %{ $stats } ) )
    {   
        for my $method ( keys( %{ $stats->{ $story_set } } ) )
        {
            for my $v ( qw(mean_length sd_length num_short_stories) )
            {
                print "$story_set: $v $method $stats->{ $story_set }->{ $method }->{ $v }\n";
            }
        }
    }
}

main();
