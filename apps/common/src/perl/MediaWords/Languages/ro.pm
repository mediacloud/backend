package MediaWords::Languages::ro;

use strict;
use warnings;

use base 'MediaWords::Languages::Language::PythonWrapper';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

sub _python_language_class_path
{
    return 'mediawords.languages.ro';
}

sub _python_language_class_name
{
    return 'RomanianLanguage';
}

1;
