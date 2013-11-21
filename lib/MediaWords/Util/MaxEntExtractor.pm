package MediaWords::Util::MaxEntExtractor;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;

use Data::Dumper;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);

#use List::MoreUtils qw( :all);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use IPC::Open2;

use Moose;

with 'MediaWords::Util::Extractor';

sub getScoresAndLines
{
    my ( $self, $line_infos, $preprocessed_lines ) = @_;

    my $extracted_lines = get_extracted_line_with_maxent( $line_infos, $preprocessed_lines );

    return {
        included_line_numbers => $extracted_lines,
        scores                => [],
    };
}

sub getExtractedLines
{
    my ( $self, $line_infos, $preprocessed_lines ) = @_;

    return get_extracted_line_with_maxent( $line_infos, $preprocessed_lines );
}

sub get_extracted_line_with_maxent
{
    my ( $line_infos, $preprocessed_lines ) = @_;

    my $ea = each_arrayref( $line_infos, $preprocessed_lines );

    my $extracted_lines = [];

    my $last_in_story_line;

    my $line_num = 0;

    #TODO DRY out this code so it doesn't duplicate mediawords_extractor_test_to_features.pl
    my $previous_states = [ qw ( prestart 'start' ) ];

    while ( my ( $line_info, $line_text ) = $ea->() )
    {

        my $prior_state_string = join '_', @$previous_states;
        $line_info->{ "priors_$prior_state_string" } = 1;
        if ( $previous_states->[ 1 ] eq 'auto_excluded' )
        {
            $line_info->{ previous_line_auto_excluded } = 1;
        }

        shift $previous_states;

        if ( $line_info->{ auto_excluded } == 1 )
        {
            push $previous_states, 'auto_excluded';
            next if $line_info->{ auto_excluded } == 1;
        }

        my $line_number = $line_info->{ line_number };

        if ( defined( $last_in_story_line ) )
        {
            $line_info->{ distance_from_previous_in_story_line } = $line_number - $last_in_story_line;
        }

        MediaWords::Crawler::AnalyzeLines::add_additional_features( $line_info, $line_text );

        my $feature_string = MediaWords::Crawler::AnalyzeLines::get_feature_string_from_line_info( $line_info, $line_text );

        #say STDERR "got feature_string: $feature_string";

        my $model_result = pipe_to_streaming_model( $feature_string );

        #say STDERR Dumper( $model_result );

        my $prediction = reduce { $model_result->{ $a } > $model_result->{ $b } ? $a : $b } keys %{ $model_result };

        if ( $model_result->{ excluded } < 0.85 )
        {
            push $extracted_lines, $line_info->{ line_number };
            $last_in_story_line = $line_number;

            #say STDERR "including line because of exclude prob:  $model_result->{ excluded } ";
        }
        else
        {

            #say STDERR "Excluded line because of exclude prob:  $model_result->{ excluded } ";
        }

        push $previous_states, $prediction;

        #say Dumper( $model_result );
    }

    return $extracted_lines;
}

my $chldout;
my $chldin;
my $pid;

sub pipe_to_streaming_model
{
    my ( $feature_string ) = @_;

    die unless $feature_string;

    if ( !defined( $chldout ) )
    {
        my $script_path =
          '~/ML_code/apache-opennlp-1.5.2-incubating-src/opennlp-maxent/samples/sports_dev/run_predict_stream_input.sh';

        #my $model_path = 'training_data_features_top_1000_unigrams_2_prior_states_MaxEntModel_Iterations_1500.txt';
        my $model_path = 'training_data_features_top_1000_unigrams_no_prior_states_MaxEntModel_Iterations_1000.txt';

        my $cmd = "$script_path $model_path";

        say STDERR "Starting cmd:\n$cmd";

        $pid = open2( $chldout, $chldin, "$cmd" );

        use POSIX ":sys_wait_h";

        sleep 2;

        my $reaped_pid = waitpid( $pid, WNOHANG );

        die if ( $reaped_pid == $pid );
    }

    #say STDERR "sending '$feature_string'";

    say $chldin $feature_string;

    my $string = <$chldout>;

    my $reaped_pid = waitpid( $pid, WNOHANG );

    die $string if ( $reaped_pid == $pid );

    my $prob_strings = [ split /\s+/, $string ];

    #say Dumper( $prob_strings );

    my $prob_hash = {};

    foreach my $prob_string ( @{ $prob_strings } )
    {
        $prob_string =~ /([a-z]+)\[([0-9.]+)\]/;

        die "Invalid prob string '$prob_string' from '$string'" unless defined( $1 ) && defined( $2 );

        $prob_hash->{ $1 } = $2;

    }

    return $prob_hash;
}

1;
