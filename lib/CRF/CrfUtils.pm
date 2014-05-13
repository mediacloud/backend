package CRF::CrfUtils;

#
# Facade to either Inline::Java based or a web service-based CRF model runner
#

use strict;
use warnings;

use MediaWords::Util::Config;

# Name of a loaded and active CRF module, either 'CRF::CrfUtils::InlineJava' or
# 'CRF::CrfUtils::WebService'.
#
# Loading of the module is postponed because CRF::CrfUtils::InlineJava compiles
# a Java class and loads it into a JVM in BEGIN{}, which slows down scripts
# that don't have anything to do with extraction
my $_active_crf_module = undef;

sub _load_and_return_crf_module()
{
    unless ( $_active_crf_module )
    {
        my $module;
        my $config = MediaWords::Util::Config->get_config();

        if ( $config->{ crf_web_service }->{ enabled } eq 'yes' )
        {
            $module = 'CRF::CrfUtils::WebService';
        }
        else
        {
            $module = 'CRF::CrfUtils::InlineJava';
        }

        eval {
            ( my $file = $module ) =~ s|::|/|g;
            require $file . '.pm';
            $module->import();
            1;
        } or do
        {
            my $error = $@;
            _fatal_error( "Unable to load $module: $error" );
        };

        $_active_crf_module = $module;
    }

    return $_active_crf_module;
}

sub create_model($$)
{
    my ( $training_data_file, $iterations ) = @_;

    my $module = _load_and_return_crf_module();

    return $module->create_model( $training_data_file, $iterations );
}

sub run_model_inline_java_data_array($$)
{
    my ( $model_file_name, $test_data_array ) = @_;

    my $module = _load_and_return_crf_module();

    return $module->run_model_inline_java_data_array( $model_file_name, $test_data_array );
}

# Helper
sub _fatal_error($)
{
    # There are errors that cannot be classified as extractor errors (that
    # would get logged into the database). For example, if the whole CRF model
    # runner web service is down, no extractions of any kind can happen anyway,
    # so it's not worthwhile to write a gazillion "extractor error: CRF web
    # service is down" errors to the database.
    #
    # Instead, we go the radical way of killing the whole extractor process. It
    # is more likely that someone will notice that the CRF model runner web
    # service is malfunctioning if the extractor gets shut down.
    #
    # Usual die() wouldn't work here because it is (might be) wrapped into an
    # eval{}.

    my $error_message = shift;

    say STDERR $error_message;
    exit 1;
}

1;
