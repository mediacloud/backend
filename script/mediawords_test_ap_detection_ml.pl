#!/usr/bin/env perl

#
# test use of machine learning to use supervised learning to detect ap syndication
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::DB;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories::AP;
use MediaWords::Util::CSV;

# use AI::FANN qw(:all);
use AI::DecisionTree;

# use Algorithm::DecisionTree;
use Digest::MD5 qw(md5);

sub get_story_content
{
    my ( $db, $story ) = @_;

    return '' unless ( $story && $story->{ download } && ( $story->{ download }->{ state } = 'success' ) );

    my $content_ref;

    eval { $content_ref = MediaWords::DBI::Downloads::fetch_content( $db, $story->{ download } ) };
    if ( $@ || !$content_ref )
    {
        warn( "error fetching content: $@" );
        return 0;
    }

    return $$content_ref;
}

sub get_ap_dup_sentence_lengths
{
    my ( $db, $story ) = @_;

    my ( $ap_media_id ) = $db->query( "select media_id from media where name = 'Associated Press - Full Feed'" )->flat;

    my $sentences = $db->query( <<SQL )->hashes;
with sentence_md5s as (
    select md5( ss.sentence ) md5_sentence
        from story_sentences ss
        where ss.stories_id = $story->{ stories_id } and
        ss.media_id <> 209366
)

select * from story_sentences
    where media_id = 209366 and
        md5( sentence ) in ( select md5_sentence from sentence_md5s );
SQL

    my $sentence_lengths = [ map { length( $_->{ sentence } ) } @{ $sentences } ];

    return $sentence_lengths;
}

sub get_content_pattern_matches
{
    my ( $db, $story, $pattern, $restrict_to_first ) = @_;

    my $content = get_story_content( $db, $story );

    if ( $restrict_to_first )
    {
        $content = substr( $content, 0, int( length( $content ) * $restrict_to_first ) );
    }

    my @matches = $content =~ /$pattern/;

    return scalar( @matches );
}

sub get_text_pattern_matches
{
    my ( $db, $story, $pattern ) = @_;

    my $text = MediaWords::DBI::Stories::get_text( $db, $story );

    my @matches = $text =~ /$pattern/;

    return scalar( @matches );
}

sub get_sentence_pattern_matches
{
    my ( $db, $story, $pattern ) = @_;

    my $sentences = $db->query( "select sentence from story_sentences where stories_id = ?", $story->{ stories_id } )->flat;

    my $text = join( ' ', @{ $sentences } );

    my @matches = $text =~ /$pattern/;

    return scalar( @matches );
}

my $_cached_features;

sub get_cached_features
{
    my ( $db ) = @_;

    if ( !$_cached_features )
    {
        my $features = $db->query( "select * from scratch.ap_story_nn_features" )->hashes;
        map { $_cached_features->{ $_->{ stories_id } }->{ $_->{ name } } = $_->{ value } } @{ $features };
    }

    return $_cached_features;
}

my $_features_queue = [];

sub save_feature
{
    my ( $db, $story, $name, $value ) = @_;

    push( @{ $_features_queue }, [ $story->{ stories_id }, $name, $value ] );

    save_features_queue( $db ) if ( scalar( @{ $_features_queue } ) > 500 );
}

sub save_features_queue
{
    my ( $db ) = @_;

    return unless scalar( @{ $_features_queue } );

    say STDERR "save features ...";

    my $values = [];
    for my $feature ( @{ $_features_queue } )
    {
        my $stories_id = $feature->[ 0 ];
        my $q_name     = $db->dbh->quote( $feature->[ 1 ] );
        my $q_value    = $db->dbh->quote( $feature->[ 2 ] );

        push( @{ $values }, "($stories_id, $q_name, $q_value)" );
    }

    my $values_list = join( ',', @{ $values } );

    $db->query( <<SQL );
insert into scratch.ap_story_nn_features ( stories_id, name, value ) values $values_list
SQL

    $_features_queue = [];
}

sub set_feature
{
    my ( $db, $story, $name, $func ) = @_;

    my $cached_features = get_cached_features( $db );

    my $value = $cached_features->{ $story->{ stories_id } }->{ $name };

    if ( !defined( $value ) )
    {
        $value = $func->();

        save_feature( $db, $story, $name, $value );
    }

    $story->{ features }->{ $name } = $value;
}

sub get_all_string_match_positions
{
    my ( $haystack, $needle ) = @_;

    my $positions = [];
    my $offset    = 0;

    while ( ( my $pos = index( substr( $haystack, $offset ), $needle ) ) > 0 )
    {
        push( @{ $positions }, $pos + $offset );
        $offset = $offset + $pos + 1;
    }

    return $positions;
}

sub get_associated_press_near_title
{
    my ( $db, $story ) = @_;

    my $content = lc( get_story_content( $db, $story ) );

    $content =~ s/\s+/ /g;

    my $title_positions = get_all_string_match_positions( $content, lc( $story->{ title } ) );
    my $ap_positions    = get_all_string_match_positions( $content, 'associated press' );

    for my $title_p ( @{ $title_positions } )
    {
        for my $ap_p ( @{ $ap_positions } )
        {
            return 1 if ( abs( $title_p - $ap_p ) < 256 );
        }
    }

    return 0;
}

sub get_associated_press_not_near_img
{
    my ( $db, $story ) = @_;

    my $content = lc( get_story_content( $db, $story ) );

    $content =~ s/\s+/ /g;

    my $img_positions = get_all_string_match_positions( $content, 'img' );
    my $ap_positions  = get_all_string_match_positions( $content, 'associated press' );

    my $ap_count = 0;
  SKIP: for my $ap_p ( @{ $ap_positions } )
    {
        for my $img_p ( @{ $img_positions } )
        {
            if ( ( $ap_p > $img_p ) && ( ( $ap_p - $img_p ) < 256 ) )
            {
                next SKIP;
            }

            $ap_count++;
        }
    }

    return 0;
}

# * ap sports writer
# * ap economics writer
# * australian associated press

# return a hash of features useful for ai training
sub add_features_to_story
{
    my ( $db, $story ) = @_;

    say STDERR "add features to $story->{ stories_id } ...";

    my $sentence_lengths;

# set_feature( $db, $story, 'dup_sentences', sub { $sentence_lengths ||= get_ap_dup_sentence_lengths( $db, $story ); scalar( @{ $sentence_lengths } ) } );
# set_feature( $db, $story, 'dup_sentences_64', sub { $sentence_lengths ||= get_ap_dup_sentence_lengths( $db, $story ); scalar( grep { $_ >= 64 } @{ $sentence_lengths } ) } );
    set_feature(
        $db, $story,
        'dup_sentences_32',
        sub {
            $sentence_lengths ||= get_ap_dup_sentence_lengths( $db, $story );
            scalar( grep { $_ >= 32 } @{ $sentence_lengths } );
        }
    );

# set_feature( $db, $story, 'dup_sentences_16', sub { $sentence_lengths ||= get_ap_dup_sentence_lengths( $db, $story ); scalar( grep { $_ >= 16 } @{ $sentence_lengths } ) } );
#set_feature( $db, $story, 'more_than_one_dup_sentence_32', sub { $sentence_lengths ||= get_ap_dup_sentence_lengths( $db, $story ); scalar( grep { $_ >= 32 } @{ $sentence_lengths } ) > 1 } );

# set_feature( $db, $story, 'associated_press_all_imgs',
#     sub { get_content_pattern_matches( $db, $story, qr/((img.{0,256}associated press)|(associated press.{0,256}img))/i ) } );
    set_feature( $db, $story, 'associated_press_mentions',
        sub { get_content_pattern_matches( $db, $story, qr/associated press/i ) } );
    set_feature(
        $db, $story,
        'associated_press_tag_mentions',
        sub { get_content_pattern_matches( $db, $story, qr/\<[^\<\>]*associated press[^\<\>]*\>/i ) }
    );
    set_feature(
        $db, $story,
        'quoted_associated_press_mentions',
        sub { get_content_pattern_matches( $db, $story, qr/["\'\|].{0,8}associated press.{0,8}["\'\|]/i ) }
    );
    set_feature(
        $db, $story,
        'quoted_associated_press_first_quarter_mentions',
        sub { get_content_pattern_matches( $db, $story, qr/["\'\|].{0,8}associated press.{0,8}["\'\|]/i ) }, 0.25
    );
    set_feature( $db, $story, 'ap_online_mentions', sub { get_content_pattern_matches( $db, $story, qr/ap_online/i ) } );
    set_feature( $db, $story, 'ap_copyright_mentions',
        sub { get_content_pattern_matches( $db, $story, qr/copyright.{0,8}associated press/i ) } );

    set_feature( $db, $story, 'ap_news_mentions', sub { get_content_pattern_matches( $db, $story, qr/ap news/i ) } );

    set_feature( $db, $story, 'associated_press_near_title', sub { get_associated_press_near_title( $db, $story ) } );

    set_feature( $db, $story, 'associated_press_not_near_img', sub { get_associated_press_not_near_img( $db, $story ) } );

    set_feature( $db, $story, 'ap_mentions',           sub { get_text_pattern_matches( $db, $story, qr/\(ap\)/i ) } );    #
    set_feature( $db, $story, 'ap_mentions_uppercase', sub { get_text_pattern_matches( $db, $story, qr/\(AP\)/ ) } );     #
    set_feature(
        $db, $story,
        'ap_mentions_uppercase_location',
        sub { get_text_pattern_matches( $db, $story, qr/[A-Z]+\s*\(AP\)/ ) }
    );

    set_feature( $db, $story, 'ap_mentions_sentences', sub { get_sentence_pattern_matches( $db, $story, qr/\(ap\)/i ) } );
}

sub get_skip_stories_lookup
{
    my ( $db, $stories, $method ) = @_;

    my $stories_id_list = join( ',', map { $_->{ stories_id } } @{ $stories } );

    my $skip_stories = $db->query( <<SQL, $method )->hashes;
select *
    from scratch.ap_stories_detected
    where stories_id in ( $stories_id_list ) and
        method = ?
SQL

    my $skip_stories_lookup = {};
    map { $skip_stories_lookup->{ $_->{ stories_id } } = 1; } @{ $skip_stories };

    return $skip_stories_lookup;
}

sub insert_detected_stories
{
    my ( $db, $stories, $method ) = @_;

    return if ( !@{ $stories } );

    my $q_method = $db->dbh->quote( $method );

    my $values = [];
    for my $s ( @{ $stories } )
    {
        my $b_ap = $s->{ ai_ap_detected } ? 'true' : 'false';

        push( @{ $values }, "($s->{ stories_id },$q_method,$b_ap)" );
    }

    my $values_list = join( ',', @{ $values } );

    $db->query( <<SQL );
insert into scratch.ap_stories_detected ( stories_id, method, syndicated )
values $values_list
SQL

}

sub attach_downloads_to_stories
{
    my ( $db, $stories ) = @_;

    my $stories_id_list = join( ',', map { $_->{ stories_id } } @{ $stories } );

    my $downloads = $db->query( <<SQL )->hashes;
select * from downloads
    where stories_id in ( $stories_id_list )
    order by downloads_id;
SQL

    my $downloads_lookup = {};
    for my $download ( @{ $downloads } )
    {
        next if ( $downloads_lookup->{ $download->{ stories_id } } );

        $downloads_lookup->{ $download->{ stories_id } } = $download;
    }

    map { $_->{ download } = $downloads_lookup->{ $_->{ stories_id } } } @{ $stories };
}

# shuffle the stories list randomly and return the first half of the list for
# training and the second half for evaluation
sub split_stories_for_training
{
    my ( $stories ) = @_;

    my $num_stories = scalar( @{ $stories } );

    # my $random_sort_stories = [ sort { md5( $a->{ stories_id } ) cmp md5( $b->{ stories_id } ) } @{ $stories } ];
    #
    # my $training_stories = $random_sort_stories;

    my $training_stories = [ @{ $stories } ];
    my $evaluation_stories = [ splice( @{ $training_stories }, $num_stories / 2 ) ];

    return ( $training_stories, $evaluation_stories );
}

sub get_stories
{
    my ( $db, $method ) = @_;

    my $stories = $db->query( <<SQL, $method )->hashes;
select
        s.*,
        ( ap.syndication = 'ap' ) ap_coded,
        ap.syndication,
        ap.url_status,
        ap.set,
        d.syndicated ai_ap_detected
    from
        stories s
        join scratch.ap_stories_coded ap on ( s.stories_id = ap.stories_id )
        left join scratch.ap_stories_detected d on ( s.stories_id = d.stories_id and method = ? )
    order by ( s.stories_id % 101 );
SQL

    attach_downloads_to_stories( $db, $stories );

    # my $skip_stories_lookup = get_skip_stories_lookup( $db, $stories, $method );
    #
    # my $pruned_stories = [];
    # map { push( @{ $pruned_stories }, $_ ) unless ( $skip_stories_lookup->{ $_->{ stories_id } } );
    # $stories = $pruned_stories;

    return $stories;
}

my $_nn_feature_names;

sub get_nn_features_vector
{
    my ( $story ) = @_;

    my $features = get_tree_normalized_features( $story );

    $_nn_feature_names ||= [ keys( %{ $features } ) ];

    my $features_vector = [];
    map { push( @{ $features_vector }, $features->{ $_ } ) } @{ $_nn_feature_names };

    return $features_vector;
}

sub get_training_vector
{
    my ( $stories ) = @_;

    die( "empty stories" ) unless ( @{ $stories } );

    my $vector = [];
    for my $story ( @{ $stories } )
    {
        my $features_vector = get_nn_features_vector( $story );

        my $ap_value = $story->{ ap_coded } ? 1 : -1;

        push( @{ $vector }, $features_vector, [ $ap_value ] );
    }

    return $vector;
}

sub get_trained_ai_nn
{
    my ( $stories ) = @_;

    die( "empty stories" ) unless ( @{ $stories } );

    my $vector = get_training_vector( $stories );

    my $input_neurons = scalar( @{ $vector->[ 0 ] } );

    my $ann = AI::FANN->new_standard( $input_neurons, int( $input_neurons * 2 ), 1 );

    # $ann->hidden_activation_function( FANN_SIGMOID_SYMMETRIC );
    # $ann->output_activation_function( FANN_SIGMOID_SYMMETRIC );

    my $train = AI::FANN::TrainData->new( @{ $vector } );

    say STDERR "running training ...";

    $ann->train_on_data( $train, 5000, 1000, 0.001 );

    my $file = "ap_nn_machines/" . time() . "-$$.ann";

    say STDERR "saving machine to $file";

    $ann->save( $file );

    return $ann;
}

# convert values to a small number of values
sub get_tree_normalized_features
{
    my ( $story ) = @_;

    my $f = { %{ $story->{ features } } };

    # convert values to booleans to avoid overfitting to specific values
    while ( my ( $name, $value ) = each( %{ $f } ) )
    {
        if ( $value > 10 )
        {
            $f->{ $name } = 2;
        }
        elsif ( $value > 1 )
        {
            $f->{ $name } = 1;
        }
    }

    return $f;
}

# convert values to booleans
sub get_boolean_features
{
    my ( $story ) = @_;

    my $f = { %{ $story->{ features } } };

    # convert values to booleans to avoid overfitting to specific values
    while ( my ( $name, $value ) = each( %{ $f } ) )
    {
        if ( $value > 1 )
        {
            $f->{ $name } = 1;
        }
    }

    return $f;
}

sub get_trained_ai_dt
{
    my ( $stories ) = @_;

    my $ai = new AI::DecisionTree( noise_mode => 'pick_best', verbose => 1 );

    for my $story ( @{ $stories } )
    {
        my $f = get_tree_normalized_features( $story );

        $ai->add_instance( attributes => $f, result => $story->{ ap_coded } );
    }

    $ai->train;

    say STDERR Dumper( $ai->rule_tree );

    # my $gv = $ai->as_graphviz;
    #
    # $gv->as_plain( 'ap_dt.txt' );

    return $ai;
}

sub get_trained_ai_alg_dt
{
    my ( $stories ) = @_;

    my $features_list = [];
    for my $story ( @{ $stories } )
    {
        my $f = get_tree_normalized_features( $story );
        $f->{ ap_coded }   = $story->{ ap_coded };
        $f->{ stories_id } = $story->{ stories_id };
        push( @{ $features_list }, $f );
    }

    my $field_names = [ 'stories_id', 'ap_coded', keys( %{ $stories->[ 0 ]->{ features } } ) ];

    my $encoded_csv = MediaWords::Util::CSV::get_hashes_as_encoded_csv( $features_list, $field_names );

    my $csv_file = '/tmp/ap_stories_dt.csv';
    open( FILE, ">$csv_file" ) || die( "Unable to open csv file '$csv_file': $!" );
    print FILE $encoded_csv;
    close( FILE );

    my $ai = Algorithm::DecisionTree->new(
        training_datafile        => $csv_file,
        csv_class_column_index   => 1,
        csv_columns_for_features => [ 2 .. ( scalar( @{ $field_names } ) - 1 ) ],
        entropy_threshold        => 0.0001,
        debug1                   => 1,
    );

    $ai->get_training_data();

    $ai->evaluate_training_data();

    $ai->calculate_first_order_probabilities();
    $ai->calculate_class_priors();

    my $root_node = $ai->construct_decision_tree_classifier();

    $ai->{ _mc_root_node } = $root_node;

    $root_node->display_decision_tree( " " );

    # $ai->show_training_data;

    return $ai;

}

sub get_trained_ai
{
    my ( $stories ) = @_;

    return get_trained_ai_dt( $stories );
}

sub get_ai_result_dt
{
    my ( $ai, $story ) = @_;

    my $f = get_tree_normalized_features( $story );

    my $raw = $ai->get_result( attributes => $f );

    return ( $raw, $raw );
}

sub get_ai_result_nn
{
    my ( $nn, $story ) = @_;

    my $results = $nn->run( get_nn_features_vector( $story ) );

    my $raw = $results->[ 0 ];

    my $boolean = ( $raw > 0 ) ? 1 : 0;

    return ( $raw, $boolean );
}

sub get_ai_result_alg_dt
{
    my ( $ai, $story ) = @_;

    my $features = get_tree_normalized_features( $story );

    my $vector = [];
    while ( my ( $name, $value ) = each( %{ $features } ) )
    {
        push( @{ $vector }, "$name=$value" );
    }

    my $raw = $ai->classify( $ai->{ _mc_root_node }, $vector );

    my $percent = $raw->{ 'ap_coded=1' };

    return ( $percent, ( $percent > 0.5 ) );
}

sub get_ai_result_nnh
{
    my ( $ai, $story ) = @_;

    my $features = get_boolean_features_vector( $story );

    return $ai->evaluate( @{ $features } );
}

sub get_ai_result
{
    my ( $ai, $story ) = @_;

    return get_ai_result_dt( $ai, $story );
}

sub print_story_results_with_features
{
    my ( $story ) = @_;

    my $features_dump = $story->{ features } ? Dumper( $story->{ features } ) : '';

    $story->{ ai_ap_raw } = $story->{ ai_ap_detected } unless ( defined( $story->{ ai_ap_raw } ) );

    print <<END;
$story->{ stories_id } [$story->{ media_id }] coded: $story->{ ap_coded } detected: $story->{ ai_ap_detected } ($story->{ ai_ap_raw })
$features_dump
END

}

sub print_results
{
    my ( $stories ) = @_;

    my ( $correct, $fp, $fn ) = ( [], [], [] );

    for my $story ( @{ $stories } )
    {
        my $coded    = $story->{ ap_coded };
        my $detected = $story->{ ai_ap_detected };

        if ( $coded && $detected )
        {
            push( @{ $correct }, $story );
        }
        elsif ( $detected )
        {
            push( @{ $fp }, $story );
        }
        elsif ( $coded )
        {
            push( @{ $fn }, $story );
        }

        # print "$story->{ stories_id } coded: $story->{ ap_coded } detected: $story->{ ai_ap_detected }\n";
    }

    my $num_correct        = scalar( @{ $correct } );
    my $num_false_positive = scalar( @{ $fp } );
    my $num_false_negative = scalar( @{ $fn } );

    if ( !$num_correct )
    {
        print "NONE CORRECT\n";
        return;
    }

    my $p_false_positive = $num_false_positive / ( $num_correct + $num_false_positive );
    my $p_false_negative = $num_false_negative / ( $num_correct + $num_false_negative );

    print "FALSE POSITIVES:\n";
    map { print_story_results_with_features( $_ ) } sort { $a->{ media_id } <=> $b->{ media_id } } @{ $fp };
    print "FALSE NEGATIVES:\n";
    map { print_story_results_with_features( $_ ) } sort { $a->{ media_id } <=> $b->{ media_id } } @{ $fn };

    print <<END;
correct: $num_correct
false_positive: $num_false_positive ($p_false_positive)
false_negative: $num_false_negative ($p_false_negative)

END

}

sub get_evaluation_stories
{
    my ( $db ) = @_;

    my $stories = $db->query( <<SQL )->hashes;
select
        s.*,
        ( ap.syndication = 'ap' ) ap_coded,
        ap.syndication,
        ap.url_status
    from
        stories s
        join scratch.ap_stories_coded ap on ( s.stories_id = ap.stories_id )
    order by stories_id;
SQL

    attach_downloads_to_stories( $db, $stories );

    map { add_features_to_story( $db, $_ ) } @{ $stories };
    save_features_queue( $db );

    return $stories;
}

sub main
{
    my ( $method ) = @ARGV;

    $| = 1;

    my $db = MediaWords::DB::connect_to_db;

    my $stories = get_stories( $db, $method );

    my ( $training_stories, $evaluation_stories ) = split_stories_for_training( $stories );

    if ( $method =~ /^module/ )
    {
        splice( @{ $evaluation_stories }, 100 );
        my $save_story_results = [];
        for my $story ( @{ $evaluation_stories } )
        {
            if ( !defined( $story->{ ai_ap_detected } ) )
            {
                print STDERR "detecting $story->{ stories_id } ...";
                $story->{ ai_ap_detected } = MediaWords::DBI::Stories::AP::is_syndicated( $db, $story, 1 );
                my $result = $story->{ ai_ap_detected } ? 'AP' : 'NOT';
                say STDERR $result;

                insert_detected_stories( $db, [ $story ], $method );
                $story->{ features } = $story->{ ap_features };
            }
        }

        print_results( $evaluation_stories );
    }
    else
    {
        map { add_features_to_story( $db, $_ ) } @{ $stories };
        save_features_queue( $db );

        my $ai = get_trained_ai( $training_stories );

        # my $evaluation_stories = get_evaluation_stories( $db );

        for my $s ( @{ $evaluation_stories } )
        {
            my ( $raw, $boolean ) = get_ai_result( $ai, $s );
            $s->{ ai_ap_raw }      = $raw;
            $s->{ ai_ap_detected } = $boolean;
        }

        print_results( $evaluation_stories );

        if ( $method )
        {
            insert_detected_stories( $db, $evaluation_stories, $method );
        }
    }
}

main();
