package MediaWords::Languages::ja;

#
# Japanese
#

use strict;
use warnings;
use utf8;

use Moose;
with 'MediaWords::Languages::Language';

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

# Import McJapaneseTokenizer
import_python_module( __PACKAGE__, 'mediawords.languages.ja' );

use Readonly;

sub BUILD
{
    my ( $self, $args ) = @_;

    my $tokenizer = MediaWords::Languages::ja::McJapaneseTokenizer->new();

    # Quick self-test to make sure that MeCab, its dictionaries and Python
    # class are installed and working
    my @self_test_words = $tokenizer->tokenize_sentence_to_words( 'pythonが大好きです' );
    if ( ( !$self_test_words[ 0 ] ) or $self_test_words[ 1 ] ne '大好き' )
    {
        die <<EOF;
MeCab self-test failed; make sure that MeCab is installed and dictionaries are accessible:

    git submodule update --init --recursive
    ./install/install_mecab-ipadic-neologd.sh

EOF
    }

    $self->{ _japanese_tokenizer } = $tokenizer;
}

sub get_language_code
{
    return 'ja';
}

sub fetch_and_return_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/ja_stopwords.txt' );
}

sub stem
{
    my $self = shift;

    # MeCab's sentence -> word tokenizer already returns "base forms" of every word
    return \@_;
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;

    my $sentences = $self->{ _japanese_tokenizer }->tokenize_text_to_sentences( $story_text );

    return $sentences;
}

sub tokenize
{
    my ( $self, $sentence ) = @_;

    my $words = $self->{ _japanese_tokenizer }->tokenize_sentence_to_words( $sentence );

    return $words;
}

1;
