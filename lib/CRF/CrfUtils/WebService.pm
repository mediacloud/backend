package CRF::CrfUtils::WebService;

use strict;
use warnings;

use MediaWords::Util::Config;

BEGIN
{
    # FIXME
}

sub create_model($$$)
{
    my ( $class, $training_data_file, $iterations ) = @_;

    # FIXME
}

sub run_model($$$$)
{
    my ( $class, $model_file_name, $test_data_file, $output_fhs ) = @_;

    # FIXME
}

sub run_model_with_tmp_file($$$)
{
    my ( $class, $model_file_name, $test_data_array ) = @_;

    # FIXME
}

sub run_model_with_separate_exec($$$)
{
    my ( $class, $model_file_name, $test_data_array ) = @_;

    # FIXME
}

sub run_model_inline_java_data_array($$$)
{
    my ( $class, $model_file_name, $test_data_array ) = @_;

    # FIXME
}

sub train_and_test($$$$)
{
    my ( $class, $files, $output_fhs, $iterations ) = @_;

    # FIXME
}

1;
