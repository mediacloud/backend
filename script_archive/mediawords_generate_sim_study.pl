#!/usr/bin/perl -w

# generate the story pairs for the similarity study

use strict;

use encoding "utf8";

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use MediaWords::DBI::Stories;
use MediaWords::Languages::Language;
use MediaWords::Util::Web;

use Text::CSV_XS;

# start and end date of sample
use constant SAMPLE_START_DATE => '2010-04-01';
use constant SAMPLE_END_DATE   => '2011-04-01';

# if SAMPLE_KEYWORDS is not empty, include only stories that include
# at least one of these keywords
use constant SAMPLE_KEYWORDS =>
  qw(путин Медведев кудрин Египет Тунис протест беспорядки пожар смог добровольцы лес мигалки ведерки метро Взрывы теракт культуры Лубянка домодедово взрыв теракт аеропорт Кашин Химки Селигер Наши Ходорковский ЮКОС модернизация Скoлково инновация инноград коррупция прозрачность подотчетность);

# the range to use to sample the story pairs by similarity -- so a range of 0.25
# means that we will pull equal numbers of story pairs from those pairs that
# have similarities of 0 - 0.25, 0.25 - 0.5, 0.5 - 0.75, 0.75 - 1.0
use constant SAMPLE_RANGE => 0.10;

# number of pairs to pull from each sample range
use constant SAMPLE_RANGE_PAIRS => 10;

# tags_id of tag marking which blog media sources to include
use constant BLOG_MEDIA_TAGS_IDS => ( 8875024 );

# tags_id of tag marking which msm feeds to include
use constant MSM_MEDIA_TAGS_IDS => ( 8875073, 8875076, 8875077, 8875078, 8875079, 8875084, 8875087 );

# stories to query, before correcting for equal blogs / msm and keywords filtering
use constant STORY_QUERY_LIMIT => 5000;

# exclude the following media sources
use constant EXCLUDE_MEDIA_IDS => ( 1762 );

# get the set of stories belonging to study sets and feeds for the week following the given date
sub get_stories
{
    my ( $db ) = @_;

    my $tags_list = join( ',', BLOG_MEDIA_TAGS_IDS, MSM_MEDIA_TAGS_IDS );
    my $exclude_media_ids_list = join( ',', EXCLUDE_MEDIA_IDS );

    my $all_stories = $db->query(
        "select s.*, mtm.tags_id from stories s, media_tags_map mtm " .
          "  where s.media_id = mtm.media_id and mtm.tags_id in ( $tags_list ) " .
          "    and date_trunc( 'day', s.publish_date ) between ?::date and ?::date " .
          "    and s.media_id not in ( $exclude_media_ids_list ) " . "    order by random() limit " . STORY_QUERY_LIMIT,
        SAMPLE_START_DATE, SAMPLE_END_DATE
    )->hashes;

    print STDERR "all stories: " . scalar( @{ $all_stories } ) . "\n";

    # the above query takes a Long Time, including a seq scan of stories, so we
    # just do it once and then sort throught the results in perl to make sure
    # we have equal numbers of msm and blog stories
    my $blog_tags_lookup = {};
    map { $blog_tags_lookup->{ $_ } = 1 } BLOG_MEDIA_TAGS_IDS;

    my $blog_stories = [];
    my $msm_stories  = [];
    for my $story ( @{ $all_stories } )
    {
        if ( $blog_tags_lookup->{ $story->{ tags_id } } )
        {
            push( @{ $blog_stories }, $story );
        }
        else
        {
            push( @{ $msm_stories }, $story );
        }
    }

    print STDERR "blog stories: " . scalar( @{ $blog_stories } ) . "\n";
    print STDERR "msm stories: " . scalar( @{ $msm_stories } ) . "\n";

    if ( @{ $blog_stories } > @{ $msm_stories } )
    {
        splice( @{ $blog_stories }, @{ $msm_stories } );
    }
    elsif ( @{ $msm_stories } > @{ $blog_stories } )
    {
        splice( @{ $msm_stories }, @{ $blog_stories } );
    }

    push( @{ $msm_stories }, @{ $blog_stories } );

    return $msm_stories;
}

# given a list of stories with similarity scores included, produce a set of story pairs
# in the form { similarity => $s, $stories => [ $story_1, $story_2 ] }
sub get_story_pairs
{
    my ( $stories ) = @_;

    my $story_pairs = [];

    for ( my $i = 1 ; $i < @{ $stories } ; $i++ )
    {
        for ( my $j = 0 ; $j < $i ; $j++ )
        {
            my $sim = $stories->[ $i ]->{ similarities }->[ $j ];

            # throw away most low similarity stories to avoid making copies
            # if ( ( $sim >= 0.2 ) && !int( rand( 5 ) ) )
            # {
            push(
                @{ $story_pairs },
                {
                    similarity => $stories->[ $i ]->{ similarities }->[ $j ],
                    stories    => [ $stories->[ $i ], $stories->[ $j ] ]
                }
            );

            # }
        }
    }

    my @sorted_pairs = sort { $a->{ similarity } <=> $b->{ similarity } } @{ $story_pairs };

    return \@sorted_pairs;
}

# verify that we can download the given urls
sub urls_are_valid
{
    my ( $urls ) = @_;

    my $responses = MediaWords::Util::Web::ParallelGet( $urls );

    my $num_valid_urls = grep { $_->is_success } @{ $responses };

    return ( $num_valid_urls == @{ $responses } );
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
    else
    {
        warn( "Unable to find SAMPLE_RANGE_PAIRS pairs within range" );
    }

    my $range_pairs = [ @{ $story_pairs }[ $start .. $end ] ];
    $range_pairs = [ sort { int( rand( 3 ) ) - 1 } @{ $range_pairs } ];

    my $pruned_range_pairs = [];
    for my $story_pair ( @{ $range_pairs } )
    {
        if ( urls_are_valid( [ map { $story_pair->{ stories }->[ $_ ]->{ url } } ( 0, 1 ) ] ) )
        {
            push( @{ $pruned_range_pairs }, $story_pair );
        }
        if ( @{ $pruned_range_pairs } >= $max_pairs )
        {
            return $pruned_range_pairs;
        }
    }

    return $pruned_range_pairs;
}

# print the story pairs in csv format
sub print_story_pairs_csv
{
    my ( $story_pairs ) = @_;

    my $csv = Text::CSV_XS->new( { binary => 1 } );

    $csv->combine(
        qw/similarity title_1 title_2 url_1 url_2 stories_id_1 stories_id_2 media_id_1 media_id2 publish_date_1 publish_date_2/
    );
    my $output = $csv->string . "\n";

    for my $story_pair ( @{ $story_pairs } )
    {
        my $sim     = $story_pair->{ similarity };
        my $stories = $story_pair->{ stories };
        my @values =
          map { ( $stories->[ 0 ]->{ $_ }, $stories->[ 1 ]->{ $_ } ) } qw/title url stories_id media_id publish_date/;
        if ( !$csv->combine( $sim, map { Encode::encode( 'utf-8', $_ ) } @values ) )
        {
            print STDERR "csv error: " . $csv->error_input . "\n";
        }
        $output .= $csv->string . "\n";
    }

    print $output;
}

# return only the stories that include at least one word from 'SAMPLE_KEYWORDS'.
# assumes that each story has a { words } field as returned by add_word_vectors with
# the keep_words argument set to true.
sub filter_for_keywords
{
    my ( $stories ) = @_;

    return $stories if ( !SAMPLE_KEYWORDS );

    my $lang = MediaWords::Languages::Language::lang();

    my $keystem_lookup = {};
    map { print STDERR "keystem: $_ " . lc( $_ ) . "\n"; $keystem_lookup->{ lc( $_ ) } = 1 }
      @{ $lang->stem( SAMPLE_KEYWORDS ) };

    my $filtered_stories = [];
    for my $story ( @{ $stories } )
    {

        # print STDERR "filter_for_keywords: " . scalar( @{ $story->{ words } } ) . " words\n";
        for my $word ( @{ $story->{ words } } )
        {

            # print STDERR "filter_for_keywords: $word->{ stem }\n";
            if ( $keystem_lookup->{ $word->{ stem } } )
            {
                push( @{ $filtered_stories }, $story );

                # print STDERR "filter_for_keywords: matched $word->{ term }\n";
                last;
            }
        }
    }

    return $filtered_stories;
}

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    my $db = MediaWords::DB::connect_to_db;

    my $study_story_pairs = [];

    print STDERR "get_stories\n";
    my $stories = get_stories( $db );

    print STDERR "got " . scalar( @{ $stories } ) . " stories\n";

    print STDERR "add word vectors\n";
    MediaWords::DBI::Stories::add_word_vectors( $db, $stories, 1 );

    print STDERR "filter for keywords\n";
    $stories = filter_for_keywords( $stories );

    print STDERR "filtered stories: " . scalar( @{ $stories } ) . "\n";

    print STDERR "add_sims\n";
    MediaWords::DBI::Stories::add_cos_similarities( $db, $stories );

    print STDERR "get_story_pairs\n";
    my $all_story_pairs = get_story_pairs( $stories );

    for ( my $floor = 0 ; $floor < 1 ; $floor += SAMPLE_RANGE )
    {
        print STDERR "$floor get_sample_pairs\n";
        my $sample_story_pairs = get_sample_pairs( $all_story_pairs, $floor );
        push( @{ $study_story_pairs }, @{ $sample_story_pairs } );
    }

    print STDERR "print_story_pairs\n";
    print_story_pairs_csv( $study_story_pairs );
}

main();
