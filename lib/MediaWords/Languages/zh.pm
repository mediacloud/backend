package MediaWords::Languages::zh;
use Moose;
with 'MediaWords::Languages::Language';

#
# Chinese
#

# (was: lib/Lingua/ZH/Chinese_version_functionalities.txt)
#
# ---
# Chinese version Functionalities
#
# 1. Word Segmenter For the word segmenter, I have used the Lingua::ZH::WordSegmenter module.
#    This class segment a Chinese sentences into words. I have modified the existing
#    MediaWords::StoryVectors module so that once the language of article is detected as Chinese,
#    word segmenter will be used to get a list of Chinese words.
#
# 2. Dictionary updating the word segmenter uses a dictionary stored in the folder lib/Lingua/ZH/.
#    One problem about the CPAN WordSegmenter module is that all the possible Chinese words are
#    refined by the dictionary. If some new words come into the language, the segmenter is not able
#    to detect. For example, foreign politicians' name might be separated into single characters.
#    To address this issue, I have written a method under the "script" folder, write_to_dict_ZH.
#    This method allows users to add a list of new words into the existing dictionary. Future work
#    could be down to automatically crawl a list of words on the websites, such as Wikipedia, to
#    add them into the dictionary.
#
# 3. Language Detection
#    In the module Lingua::ZH::MediaWords, there was a method to judge if a given text is Chinese.
#    If more than 25% of the characters are Chinese characters, the text will be processed as Chinese.
#    In this module, there are also methods to count Chinese characters and Latin letters.
#
# 4. Stop words
#    A list of 1600 stop words are selected from the most commonly used 6000 words from collected data.
#    These stop words are stored in the file MediaWords/Util/StopWords.pm.
#
# 5. Translation
#    The translate module is modified so that it automatically detects the source language and
#    translate it into English.  The module using Google Translate is utilized in this function.
#
# 6. Extractor
#    The Density function in MediaWords/Crawler/Extractor is modified to add into consideration that
#    Chinese sentences are generally shorter than English ones. Chinese characters are added more
#    weights in the calculation.
#    I have been working on this during summer 2010 under the framework of Google Summer of Code.
#    If there are questions, please contact at mico.lmg at gmal
# ---

use strict;
use warnings;
use utf8;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Encode;
use Encode::HanConvert;
use Unicode::UCD 'charinfo';
use Unicode::UCD 'general_categories';
use Lingua::ZH::WordSegmenter;

my $EOS = "\001";
my $P   = q/[。？！]/;                            ## PUNCTUATION
my $AP  = q/(？：‘|“|》|\）|\]|』|\})?/;    ## AFTER PUNCTUATION
my $PAP = $P . $AP;

# Chinese segmenter, lazy-initialized in tokenize()
has 'segmenter' => (
    is      => 'rw',
    default => 0,
);

sub get_language_code
{
    return 'zh';
}

sub fetch_and_return_tiny_stop_words
{
    my $self = shift;
    return $self->_get_stop_words_from_file( 'lib/MediaWords/Languages/resources/zh_stoplist_tiny.txt' );
}

sub fetch_and_return_short_stop_words
{
    my $self = shift;
    return $self->get_tiny_stop_words();
}

sub fetch_and_return_long_stop_words
{
    my $self = shift;
    return $self->get_tiny_stop_words();
}

sub stem
{
    my $self = shift;

    # Don't stem anything.
    return \@_;
}

sub get_word_length_limit
{
    my $self = shift;

    # In terms of pronunciation, Chinese characters (Mandarin) are strictly monosyllabic. As such,
    # words are limited to a length of five phonemes. In Romanized spelling, no more than six letters
    # are needed for any single Chinese character in standard pronunciation, being the likes of 双,
    # which is spelled "shuang" in pinyin.
    # (http://en.wikipedia.org/wiki/Longest_words#Chinese)
    return 0;    # So, no limit.
}

sub get_sentences
{
    my ( $self, $story_text ) = @_;

    # convert traditional characters into simplified characters
    $story_text = Encode::HanConvert::trad_to_simp( $story_text );

    $story_text =~ s/\n\s*\n/$EOS/gso;     ## double new-line means a different sentence.
    $story_text =~ s/($PAP)/$1$EOS/gso;
    $story_text =~ s/(\s$P)/$1$EOS/gso;    # breake also when single letter comes before punc.
    $story_text =~ s/\s/$EOS/gso;
    $story_text =~ s/$EOS+/$EOS/gso;

    my @sentences = split( /$EOS/, $story_text );
    return \@sentences;
}

sub tokenize
{
    my ( $self, $sentence ) = @_;

    # Initialize segmenter (if needed)
    if ( $self->segmenter == 0 )
    {
        my %par = ();
        $par{ 'dic_encoding' } = 'utf8';
        $par{ 'dic' }          = _base_dir() . '/lib/MediaWords/Languages/resources/zh_dict.txt';
        $self->segmenter( Lingua::ZH::WordSegmenter->new( %par ) );
    }

    # Tokenize
    my $i;
    my $segmenter = $self->segmenter;
    $sentence = encode( 'utf8', $sentence );
    my $segs = $segmenter->seg( $sentence, 'utf8' );
    my $tokens;
    @$tokens = split( / /, $segs );
    my $token;

    foreach $token ( @$tokens )
    {
        $token =~ s/[\W\d_\s]+//g;
    }

    for ( $i = 0 ; $i < $#$tokens ; $i++ )
    {
        if ( $tokens->[ $i ] eq "" )
        {
            splice @$tokens, $i, 1;
            $i--;
        }
    }

    # Remove empty / whitespace lines (might happen because of the Chinese period)
    @$tokens = grep( /\S/, @$tokens );

    return $tokens;
}

sub get_noise_strings
{
    my $self          = shift;
    my @noise_strings = (

        # FIXME add language-dependent noise strings (see en.pm for example)
    );
    return \@noise_strings;
}

sub get_copyright_strings
{
    my $self              = shift;
    my @copyright_strings = (

        # FIXME add language-dependent copyright strings (see en.pm for example)
        'copyright',
        'copying',
        '&copy;',
        'all rights reserved',
    );
    return \@copyright_strings;
}

1;
