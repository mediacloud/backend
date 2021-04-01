package MediaWords::Languages::Language::PythonWrapper;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

# Returns Python language class path, e.g. "mediawords.languages.en"
sub _python_language_class_path()
{
    LOGCONFESS "Abstract method.";
}

# Returns Python language class name, e.g. "EnglishLanguage"
sub _python_language_class_name()
{
    LOGCONFESS "Abstract method.";
}

# Set of imported Python modules (importing the same module multiple times gives out warnings)
my $imported_modules = {};

sub new($;$)
{
    my ( $class, $python_lang ) = @_;

    my $self = {};
    bless $self, $class;

    if ( $python_lang )
    {
        # Python instance already provided
        $self->{ _python_lang } = $python_lang;

    }
    else
    {
        # Python instance is to be loaded

        my $class_path = $self->_python_language_class_path();
        my $class_name = __PACKAGE__ . '::' . $self->_python_language_class_name();

        unless ( $imported_modules->{ $class_path } )
        {
            import_python_module( __PACKAGE__, $class_path );
            $imported_modules->{ $class_path } = 1;
        }

        my $python_lang = $class_name->new();

        $self->{ _python_lang } = $python_lang;
    }

    return $self;
}

sub language_code($)
{
    my $self = shift;

    my $language_code = $self->{ _python_lang }->language_code();
    return $language_code;
}

sub stop_words_map($)
{
    my $self = shift;

    my $stop_words_map = $self->{ _python_lang }->stop_words_map();
    return $stop_words_map;
}

# FIXME remove once stopword comparison is over
sub stop_words_old_map($)
{
    my $self = shift;

    my $stop_words_old_map = $self->{ _python_lang }->stop_words_old_map();
    return $stop_words_old_map;
}

sub stem_words($$)
{
    my ( $self, $words ) = @_;

    my $stems = $self->{ _python_lang }->stem_words( $words );
    return $stems;
}

sub split_text_to_sentences($$)
{
    my ( $self, $text ) = @_;

    my $sentences = $self->{ _python_lang }->split_text_to_sentences( $text );
    return $sentences;
}

sub split_sentence_to_words($$)
{
    my ( $self, $sentence ) = @_;

    my $words = $self->{ _python_lang }->split_sentence_to_words( $sentence );
    return $words;
}

1;
