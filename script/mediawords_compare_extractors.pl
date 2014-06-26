#!/usr/bin/env perl

# extract the text for the given story using the heuristic and crf extractors
use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Data::Dumper;
use Readonly;
use Statistics::Basic;

use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;

Readonly my $NUM_SAMPLED_STORIES => 50;
Readonly my $SAMPLE_MOD          => 11;

# specify story queries for which we compare a sample of stories against
# the heuristic and crc extractors
Readonly my $STORY_QUERIES => {

    'rolezinhos-controversy + spidered' => <<END,
    select s.*
        from stories s
            join controversy_stories cs on ( s.stories_id = cs.stories_id )
            left join stories_tags_map stm on ( s.stories_id = stm.stories_id and stm.tags_id = 8875452 )
        where
            cs.controversies_id = 563 and
            stm.tags_id is not null
    END
    
          'rolezinhos-controversy + unspidered' => <<END,
    select s.*
        from stories s
            join controversy_stories cs on ( s.stories_id = cs.stories_id )
            left join stories_tags_map stm on ( s.stories_id = stm.stories_id and stm.tags_id = 8875452 )
        where
            cs.controversies_id = 563 and
            stm.tags_id is null
    END
    
          'not-in-rolezinhos-controversy + portuguese-media-set' => <<END,
    select s.*
        from one_day_stories s
            join media_tags_map mtm on ( s.media_id = mtm.media_id and mtm.tags_id = 8877968 )
            left join stories_tags_map stm on ( s.stories_id = stm.stories_id and stm.tags_id = 8875452 )
        where
            stm.tags_id is null
    END
    
          'egypt-emm' => <<END,
    select s.*
        from one_day_stories s
            join media_tags_map mtm on ( s.media_id = mtm.media_id and mtm.tags_id = 8876576 )
    END
    
          'us-political-blogs' => <<END,
    select s.*
        from one_day_stories s
            join media_tags_map mtm on ( s.media_id = mtm.media_id and mtm.tags_id = 8875108 )
    END
    
          'us-top-25-msm' => <<END,
    select s.*
        from one_day_stories s
            join media_tags_map mtm on ( s.media_id = mtm.media_id and mtm.tags_id = 8875027 )
    END

    'russia-controversy + spidered' => <<END,
select s.*
    from stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id )
        left join stories_tags_map stm on ( s.stories_id = stm.stories_id and stm.tags_id = 8875452 )
    where
        cs.controversies_id = 180 and
        stm.tags_id is not null
END

    'russia-controversy + unspidered' => <<END,
select s.*
    from stories s
        join controversy_stories cs on ( s.stories_id = cs.stories_id )
        left join stories_tags_map stm on ( s.stories_id = stm.stories_id and stm.tags_id = 8875452 )
    where
        cs.controversies_id = 180 and
        stm.tags_id is null
END

};

my $_one_day_stories_created = 0;

sub get_extractor_results_for_story
{
    my ( $db, $story, $extractor_method ) = @_;

    my $downloads =
      $db->query( "select * from downloads where stories_id = ? order by downloads_id", $story->{ stories_id } )->hashes;

    my $config = MediaWords::Util::Config::get_config;

    $config->{ mediawords }->{ extractor_method } = $extractor_method;
    my $download_results = {};
    for my $download ( @{ $downloads } )
    {
        my $res;
        eval { $res = MediaWords::DBI::Downloads::extractor_results_for_download( $db, $download ) };
        if ( $res )
        {
            $res->{ text } = join( "\n", map { $res->{ download_lines }->[ $_ ] } @{ $res->{ included_line_numbers } } );
            $res->{ download } = $download;
            $download_results->{ $download->{ downloads_id } } = $res;
        }
    }

    print "extracted $story->{ url } [$extractor_method]\n";

    my $text = join( "\n****\n", map { $_->{ text } } values( %{ $download_results } ) );

    return {
        text             => $text,
        download_results => $download_results,
        story            => $story
    };
}

sub get_extractor_stats
{
    my ( $db, $stories ) = @_;

    my ( $text_lengths, $mean_text_length, $sd_text_length, $short_stories );

    my $stats = {};
    for my $method ( 'HeuristicExtractor', 'CrfExtractor' )
    {
        my $story_results = {};
        for my $story ( @{ $stories } )
        {
            $story_results->{ $story->{ stories_id } } = get_extractor_results_for_story( $db, $story, $method );
        }

        my $texts = [ map { $_->{ text } } values( %{ $story_results } ) ];

        $stats->{ $method }->{ lengths }           = [ map { length( $_ ) } @{ $texts } ];
        $stats->{ $method }->{ mean_length }       = 0 + Statistics::Basic::mean( $stats->{ $method }->{ lengths } );
        $stats->{ $method }->{ sd_length }         = 0 + Statistics::Basic::stddev( $stats->{ $method }->{ lengths } );
        $stats->{ $method }->{ short_stories }     = scalar( grep { $_ < 128 } @{ $stats->{ $method }->{ lengths } } );
        $stats->{ $method }->{ extractor_results } = $story_results;
    }

    return $stats;
}

# print a report listing the matched lines as being matched by the given methods
sub print_matched_line_report
{
    my ( $matched_line_nums, $method_results, $method_a, $method_b ) = @_;

    return unless ( @{ $matched_line_nums } );

    if ( $method_b )
    {
        print "\tLINES MATCHED BY $method_a AND $method_b:\n";
    }
    else
    {
        print "\tLINES MATCHED ONLY BY $method_a:\n";
    }

    for my $i ( @{ $matched_line_nums } )
    {
        print "\t\t$i: " . substr( $method_results->{ $method_a }->{ download_lines }->[ $i ], 0, 128 ) . "\n";
    }

    print "\n";
}

# print line by line report about every line extracted by at least one
# of the extractors for a given story set
sub print_line_report_for_story_set
{
    my ( $story_set, $stats ) = @_;

    print "LINE REPORT FOR $story_set:\n\n";

    my $methods = [ keys( %{ $stats } ) ];

    if ( @{ $methods } != 2 )
    {
        warn( "line report can be generated only for exactly two methods" );
        return;
    }

    my $stories_ids = [ keys( %{ $stats->{ $methods->[ 0 ] }->{ extractor_results } } ) ];

    for my $stories_id ( @{ $stories_ids } )
    {
        my $story_extractor_results = $stats->{ $methods->[ 0 ] }->{ extractor_results }->{ $stories_id };
        my $downloads_ids           = [ keys( %{ $story_extractor_results->{ download_results } } ) ];
        my $story                   = $story_extractor_results->{ story };

        print "\tSTORY: $story->{ stories_id }: $story->{ url }\n\n";

        for my $downloads_id ( @{ $downloads_ids } )
        {
            # download_results for each method
            my $mr = {};
            map {
                $mr->{ $_ } =
                  $stats->{ $_ }->{ extractor_results }->{ $stories_id }->{ download_results }->{ $downloads_id }
            } @{ $methods };

            my $method_0_lines  = [];
            my $method_1_lines  = [];
            my $method_01_lines = [];

            my $num_lines = scalar( @{ $mr->{ $methods->[ 0 ] }->{ download_lines } } );
            for ( my $i = 0 ; $i < $num_lines ; $i++ )
            {
                my $method_0_is_story = $mr->{ $methods->[ 0 ] }->{ scores }->[ $i ]->{ is_story };
                my $method_1_is_story = $mr->{ $methods->[ 1 ] }->{ scores }->[ $i ]->{ is_story };

                if ( $method_0_is_story && !$method_1_is_story )
                {
                    push( @{ $method_0_lines }, $i );
                }
                elsif ( $method_1_is_story && !$method_0_is_story )
                {
                    push( @{ $method_1_lines }, $i );
                }
                elsif ( $method_1_is_story && $method_0_is_story )
                {
                    push( @{ $method_01_lines }, $i );
                }
            }

            print_matched_line_report( $method_0_lines,  $mr, $methods->[ 0 ] );
            print_matched_line_report( $method_1_lines,  $mr, $methods->[ 1 ] );
            print_matched_line_report( $method_01_lines, $mr, $methods->[ 0 ], $methods->[ 1 ] );
        }

        print "\n";
    }
}

# print line by line report about every line extracted by at least one
# of the extractors
sub print_line_report
{
    my ( $stats ) = @_;

    while ( my ( $story_set, $story_set_stats ) = each( %{ $stats } ) )
    {
        print_line_report_for_story_set( $story_set, $story_set_stats );
    }
}

# print basic mean, sd, and num of short stories stats
sub print_basic_stats
{
    my ( $stats ) = @_;

    for my $story_set ( keys( %{ $stats } ) )
    {
        for my $method ( keys( %{ $stats->{ $story_set } } ) )
        {
            for my $v ( qw(mean_length sd_length short_stories) )
            {
                print "$story_set:\t$v\t$method\t$stats->{ $story_set }->{ $method }->{ $v }\n";
            }
            print "\n";
        }
    }
}

# get a sample of NUM_SAMPLED_STORIES the most recent (by stories_id) stories
# matching the given query. Provide a one_day_stories temporary table
# that allows efficient random sampling for whole media sets.
sub get_sampled_stories
{
    my ( $db, $query, $num_sampled_stories ) = @_;

    if ( !$_one_day_stories_created )
    {
        print "generating one_day_stories ...\n";
        $_one_day_stories_created = 1;
        my $mod_factor = List::Util::max( 1, int( 10 / $num_sampled_stories ) );
        $db->query( <<END );
create temporary table one_day_stories as
    select s.* from stories s
        where date_trunc( 'day', publish_date ) = '2014-03-01'
            and ( s.stories_id % $mod_factor ) = 0

END
    }

    # guess that we'll get NUM_SAMPLED_STORIES if we multiply the limit by SAMPLE_MOD
    my $inner_limit = int( $num_sampled_stories * $SAMPLE_MOD );

    # we have to create this complex subquery because otherwise the postgres
    # query planner falls back to scanning stories_media_id instead of stories_pkey
    my $sampled_query = <<END;
select distinct q.*, md5( q.stories_id::text )
    from ( 
            $query
            order by md5( s.stories_id::text ) desc 
        ) q
        join downloads d on ( q.stories_id = d.stories_id )
    where 
        d.state = 'success'
    order by md5( q.stories_id::text ) desc 
    limit $num_sampled_stories
END

    return $db->query( $sampled_query )->hashes;
}

sub main
{
    my ( $num_sampled_stories ) = @ARGV;

    $num_sampled_stories ||= $NUM_SAMPLED_STORIES;

    $| = 1;
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    my $stats = {};

    while ( my ( $name, $query ) = each( %{ $STORY_QUERIES } ) )
    {
        print "PROCESSING SET $name...\n";

        print "fetching stories ...\n";
        my $stories = get_sampled_stories( $db, $query, $num_sampled_stories );

        print "extracting stories ...\n";
        my $s = get_extractor_stats( $db, $stories );

        $stats->{ $name } = $s;
    }

    print_line_report( $stats );

    print_basic_stats( $stats );

}

main();
