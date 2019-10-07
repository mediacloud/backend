package MediaWords::Languages::Language;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Languages::Language::PythonWrapper;

import_python_module( __PACKAGE__, 'mediawords.languages.factory' );

sub _factory()
{
    return MediaWords::Languages::Language::LanguageFactory->new();
}

sub language_is_enabled($)
{
    my $language_code = shift;

    my $language_is_enabled = _factory()->language_is_enabled( $language_code );
    return $language_is_enabled + 0;
}

sub language_for_code($)
{
    my $language_code = shift;

    my $python_lang = _factory()->language_for_code( $language_code );
    unless ( defined $python_lang )
    {
        return undef;
    }

    my $lang = MediaWords::Languages::Language::PythonWrapper->new( $python_lang );
    return $lang;
}

sub default_language_code()
{
    my $default_language_code = _factory()->default_language_code();
    return $default_language_code;
}

sub default_language()
{
    my $python_lang = _factory()->default_language();
    my $lang        = MediaWords::Languages::Language::PythonWrapper->new( $python_lang );
    return $lang;
}

1;
