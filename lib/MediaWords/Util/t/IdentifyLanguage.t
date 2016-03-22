use strict;
use warnings;

use utf8;

use Test::NoWarnings;
use Test::More tests => 14;

use Readonly;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::IdentifyLanguage' );
}

Readonly my $english_text => 'The quick brown fox jumps over the lazy dog.';
Readonly my $russian_text =>
  'В чащах юга жил бы цитрус? Да, но фальшивый экземпляр!';

sub test_language_code_for_text()
{
    is( MediaWords::Util::IdentifyLanguage::language_code_for_text( $english_text ),
        'en', 'English text identified as English' );
    is( MediaWords::Util::IdentifyLanguage::language_code_for_text( $russian_text ),
        'ru', 'Russian text identified as Russian' );

    is( MediaWords::Util::IdentifyLanguage::language_code_for_text( '' ), '', 'Empty text' );

    is( MediaWords::Util::IdentifyLanguage::language_code_for_text( $russian_text, 'ru' ),
        'ru', 'Russian text with TLD identified as Russian' );
}

sub test_identification_would_be_reliable()
{
    ok( MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( $english_text ), 'English text' );
    ok( MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( $russian_text ), 'Russian text' );

    ok( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( undef ), 'Undef text' );
    ok( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( '' ),    'Empty text' );
    ok( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( 'abc' ), 'Too short text' );
    ok( !MediaWords::Util::IdentifyLanguage::identification_would_be_reliable( '______________________' ), 'Underscores' );
}

sub test_language_is_supported()
{
    ok( MediaWords::Util::IdentifyLanguage::language_is_supported( 'en' ),  'Supported language' );
    ok( !MediaWords::Util::IdentifyLanguage::language_is_supported( 'xx' ), 'Unsupported language' );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ':utf8';
    binmode $builder->failure_output, ':utf8';
    binmode $builder->todo_output,    ':utf8';

    test_language_code_for_text();
    test_identification_would_be_reliable();
    test_language_is_supported();
}

main();
