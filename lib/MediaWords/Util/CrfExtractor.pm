package MediaWords::Util::CrfExtractor;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;

use Data::Dumper;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);

#use List::MoreUtils qw( :all);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use IPC::Open2;
use Text::Trim;
use File::Spec;
use File::Basename;
use Mallet::CrfWrapper;
use MediaWords::Util::Config;

use Moose;

with 'MediaWords::Util::Extractor';

my $_model_file_name;

# has the mallet / web service stuff been initialized
my $_crf_init;

# FIXME: make path to the extractor model configurable because that way Java
# wouldn't have to use hardcoded path to the extractor model
sub get_path_to_extractor_model()
{
    my $_dirname      = dirname( __FILE__ );
    my $_dirname_full = File::Spec->rel2abs( $_dirname );

    $_model_file_name = "$_dirname_full/models/crf_extractor_model";

    #say STDERR "model_file: $_model_file_name";

    return $_model_file_name;
}

sub _initialize_crf
{
    return if ( defined( $_crf_init ) );

    $_crf_init = 1;

    $_model_file_name = get_path_to_extractor_model();

    #say STDERR "model_file: $_model_file_name";

    my $config = MediaWords::Util::Config->get_config();

    if ( $config->{ crf_web_service }->{ enabled } eq 'yes' )
    {
        Mallet::CrfWrapper::use_webservice( 1 );
    }
    else
    {
        Mallet::CrfWrapper::use_webservice( 0 );
    }

    my $crf_server_url = $config->{ crf_web_service }->{ server_url };

    Mallet::CrfWrapper::set_webservice_url( $crf_server_url );
}

sub getScoresAndLines
{
    my ( $self, $line_info, $preprocessed_lines ) = @_;

    my $scores = _get_extracted_lines_with_crf( $line_info, $preprocessed_lines );

    my @extracted_lines = map { $_->{ line_number } } grep { $_->{ is_story } } @{ $scores };

    my $extracted_lines = \@extracted_lines;

    return {
        included_line_numbers => $extracted_lines,
        scores                => $scores,
    };
}

sub getExtractedLines
{
    my ( $self, $line_infos, $preprocessed_lines ) = @_;

    my $scores_and_lines = $self->getScoresAndLines( $line_infos, $preprocessed_lines );

    return $scores_and_lines->{ included_line_numbers };
}

sub _get_extracted_lines_with_crf
{
    my ( $line_infos, $preprocessed_lines ) = @_;

    _initialize_crf;

    my $feature_strings =
      MediaWords::Crawler::AnalyzeLines::get_feature_strings_for_download( $line_infos, $preprocessed_lines );

    my $non_autoexcluded_line_infos = [ grep { !$_->{ auto_excluded } } @$line_infos ];

    die unless scalar( @$non_autoexcluded_line_infos ) == scalar( @$feature_strings );

    my $model_file_name = $_model_file_name;

    die unless defined( $model_file_name );

    #say STDERR "using model file: '$model_file_name'";

    my $results = Mallet::CrfWrapper::run_model_inline_java_data_array( $model_file_name, $feature_strings );

    my $predictions = [ map { $_->{ prediction } } @$results ];

    #say STDERR ( Dumper( $line_infos ) );
    #say STDERR Dumper( $feature_strings );
    #say STDERR ( Dumper( $predictions ) );

    unless ( scalar( @$predictions ) == scalar( @$feature_strings ) )
    {
        die "Prediction count is not equal to the feature string count.\n";
    }

    #say STDERR "non_auto_excluded_line_infos, feature_strings, predictions zipped";
    #say STDERR Dumper( [ List::MoreUtils::zip( @$non_autoexcluded_line_infos, @$feature_strings, @$predictions ) ] );

    my $line_index       = 0;
    my $prediction_index = 0;

    my @extracted_lines;

    unless ( scalar( @$predictions ) <= scalar( @$line_infos ) )
    {
        die "Prediction count is bigger than the line info count.\n";
    }

    my $scores = [];

    while ( $line_index < scalar( @{ $line_infos } ) )
    {
        my $score;

        $score->{ line_number } = $line_index;

        if ( $line_infos->[ $line_index ]->{ auto_excluded } )
        {
            $score->{ is_story }     = 0;
            $score->{ autoexcluded } = 1;
            $line_index++;
            push( @{ $scores }, $score );
            next;
        }

        my $prediction = rtrim $predictions->[ $prediction_index ];

        $score->{ predicted_class } = $prediction;

        unless ( $prediction eq 'excluded' or $prediction eq 'required' or $prediction eq 'optional' )
        {
            die 'Invalid prediction: "' . $prediction . '" for line index ' .
              $line_index . ' and prediction_index ' . $prediction_index . ': ' . Dumper( $predictions );
        }

        #say STDERR "$prediction";
        if ( $prediction ne 'excluded' )
        {
            push @extracted_lines, $line_infos->[ $line_index ]->{ line_number };
            $score->{ is_story } = 1;
        }
        else
        {
            $score->{ is_story } = 0;
        }

        $score->{ probabilities } = $results->[ $prediction_index ]->{ probabilities };

        my $exclude_probability = $score->{ probabilities }->{ excluded };

        die "Invalid exclude_probability " unless $exclude_probability >= 0 and $exclude_probability <= 1.0;

        my $include_probability = 1.0 - $exclude_probability;

        $score->{ include_probability } = $include_probability;

        $line_index++;
        $prediction_index++;

        push( @{ $scores }, $score );

    }

    return $scores;
}

sub extractor_version
{
    return 'crf-1.0';
}
1;
