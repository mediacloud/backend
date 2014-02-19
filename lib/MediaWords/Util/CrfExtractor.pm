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

use Moose;

with 'MediaWords::Util::Extractor';

my $_model_file_name;

BEGIN
{
    my $_dirname      = dirname( __FILE__ );
    my $_dirname_full = File::Spec->rel2abs( $_dirname );

    $_model_file_name = "$_dirname_full/../../CRF/models/extractor_model";

    #say STDERR "model_file: $_model_file_name";
}

# Loading of CRF::CrfUtils is postponed because it compiles + loads a Java
# class with JVM and that in turn slows down scripts that don't have anything
# to do with extraction
my $_crf_crfutils_loaded = 0;

sub _load_crf_crfutils()
{
    unless ( $_crf_crfutils_loaded )
    {
        my $module = 'CRF::CrfUtils';

        eval {
            ( my $file = $module ) =~ s|::|/|g;
            require $file . '.pm';
            $module->import();
            1;
        } or do
        {
            my $error = $@;
            die "Unable to load $module: $error";
        };

        $_crf_crfutils_loaded = 1;
    }
}

sub getScoresAndLines
{
    my ( $self, $line_info, $preprocessed_lines ) = @_;

    my $extracted_lines = get_extracted_lines_with_crf( $line_info, $preprocessed_lines );

    my $scores = [];

    my %extracted_lines_hash = map { $_ => 1 } @{ $extracted_lines };

    foreach my $line ( @{ $line_info } )
    {
        my $score = {};

        $score->{ line_number } = $line->{ line_number };
        $score->{ is_story } = defined( $extracted_lines_hash{ $line->{ line_number } } ) ? 1 : 0;

        push $scores, $score;
    }

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

sub get_extracted_lines_with_crf
{
    my ( $line_infos, $preprocessed_lines ) = @_;

    my $feature_strings =
      MediaWords::Crawler::AnalyzeLines::get_feature_strings_for_download( $line_infos, $preprocessed_lines );

    my $model_file_name = '/home/dlarochelle/mc/mediacloud-code/branches/extractor_inline_java/crf_model';

    $model_file_name = '/home/dlarochelle/mc/mediacloud-code/branches/extractor_inline_java/features_outputModel.txt';

    $model_file_name = $_model_file_name;

    #say STDERR "using model file: '$model_file_name'";

    _load_crf_crfutils();

    my $predictions = CRF::CrfUtils::run_model_inline_java_data_array( $model_file_name, $feature_strings );

    #my $predictions = CRF::CrfUtils::run_model_with_separate_exec( $model_file_name, $feature_strings );
    #my $predictions = CRF::CrfUtils::run_model_with_tmp_file( $model_file_name, $feature_strings );

    #say STDERR ( Dumper( $line_infos ) );
    #say STDERR Dumper( $feature_strings );
    #say STDERR ( Dumper( $predictions ) );

    die unless scalar( @$predictions ) == scalar( @$feature_strings );

    my $line_index       = 0;
    my $prediction_index = 0;

    my @extracted_lines;

    die unless scalar( @$predictions ) <= scalar( @$line_infos );

    while ( $line_index < scalar( @{ $line_infos } ) )
    {
        if ( $line_infos->[ $line_index ]->{ auto_excluded } )
        {
            $line_index++;
            next;
        }

        my $prediction = rtrim $predictions->[ $prediction_index ];

        die "Invalid prediction: '$prediction' for line index $line_index and prediction_index $prediction_index " .
          Dumper( $predictions )
          unless ( $prediction eq 'excluded' )
          or ( $prediction eq 'required' )
          or ( $prediction eq 'optional' );

        #say STDERR "$prediction";
        if ( $prediction ne 'excluded' )
        {
            push @extracted_lines, $line_infos->[ $line_index ]->{ line_number };
        }
        $line_index++;
        $prediction_index++;
    }

    my $extracted_lines = \@extracted_lines;
    return $extracted_lines;
}
1;
