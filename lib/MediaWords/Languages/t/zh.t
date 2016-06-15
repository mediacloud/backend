#!/usr/bin/perl
#
# Some tests ported from languagetool ('ChineseSentenceTokenizerTest.java', 'ChineseWordTokenizerTest.java'):
#
#   LanguageTool, a natural language style checker
#   Copyright (C) 2005 Daniel Naber (http://www.danielnaber.de)
#
#   This library is free software; you can redistribute it and/or
#   modify it under the terms of the GNU Lesser General Public
#   License as published by the Free Software Foundation; either
#   version 2.1 of the License, or (at your option) any later version.
#
#   This library is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#   Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public
#   License along with this library; if not, write to the Free Software
#   Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301
#   USA
#
# Some test strings copied from Wikipedia (CC-BY-SA, http://creativecommons.org/licenses/by-sa/3.0/).
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More tests => 1 + 15 + 15 + 1 + 1;
use utf8;

use MediaWords::Languages::zh;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::zh->new();

    #
    # Simple sentence tokenizer test
    #
    # "Fanny Yi Muli , the illegitimate daughter of the British feminist Mary Wollstonecraft and
    #  American businessman Gilbert · Yi Muli . Fanny was born shortly Yi Muli took Wollstonecraft
    #  abandoned in the increasingly chaotic situation of the French Revolution . The frustrated
    #  love, Wollstonecraft and philosopher Godwin established a close relationship, and,
    #  ultimately, to marry him. In 1797, Wollstonecraft died of postnatal complications, left
    #  the three-year-old Fanny and freshmen Mary Worth through Kraft Godwin Godwin tending. Four
    #  years later, Godwin married a second wife, Fanny sisters do not like the new Mrs. Godwin.
    #  In 1814, the daughter of the young wife Mary Godwin , Claire Clairmont with runaways, go
    #  to the European continent and the Romantic poet Percy Bysshe Shelley . Fanny left alone
    #  to commit suicide in 1816, when he was 22 years old."
    $test_string = <<'QUOTE';
范妮·伊姆利，是英国女权主义者玛丽·沃斯通克拉夫特与美国商人吉尔伯特·伊姆利的私生女。
在范妮出生不久，伊姆利便将沃斯通克拉夫特抛弃在了法国大革命日趋混乱的局势之中。
在经历了这次失意的爱情后，沃斯通克拉夫特与哲学家戈德温建立了亲密的关系，并最终与他结婚。
1797年，沃斯通克拉夫特死于产后并发症，将三岁的范妮与新生的玛丽·沃斯通克拉夫特·戈德温留给了戈德温一人抚育。
四年后，戈德温与第二任妻子结婚，范妮姐妹俩都不喜欢新的戈德温太太。
1814年，年少的玛丽与新戈德温太太带来的女儿克莱尔·克莱尔蒙特一同离家出走，并与浪漫主义诗人雪莱前往了欧洲大陆。
独自留下的范妮于1816年服毒自杀，时年22岁。
QUOTE

    $expected_sentences = [
'范妮·伊姆利，是英国女权主义者玛丽·沃斯通克拉夫特与美国商人吉尔伯特·伊姆利的私生女。',
'在范妮出生不久，伊姆利便将沃斯通克拉夫特抛弃在了法国大革命日趋混乱的局势之中。',
'在经历了这次失意的爱情后，沃斯通克拉夫特与哲学家戈德温建立了亲密的关系，并最终与他结婚。',
'1797年，沃斯通克拉夫特死于产后并发症，将三岁的范妮与新生的玛丽·沃斯通克拉夫特·戈德温留给了戈德温一人抚育。',
        '四年后，戈德温与第二任妻子结婚，范妮姐妹俩都不喜欢新的戈德温太太。',
'1814年，年少的玛丽与新戈德温太太带来的女儿克莱尔·克莱尔蒙特一同离家出走，并与浪漫主义诗人雪莱前往了欧洲大陆。',
        '独自留下的范妮于1816年服毒自杀，时年22岁。'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    my $t1 = "他说：";             # "He said:"
    my $t2 = "我们是中国人";    # "We are Chinese"
    my $t3 = "中国人很好";       # "Chinese people good"

    #
    # Sentence tokenizer: test 1
    #
    my @punctuation1 = ( '_', '/', ';', ':', '!', '@', '#', '$', '%', '^', '&', '.', '+', '*', '?' );
    foreach my $i ( @punctuation1 )
    {
        my $test_string = $t2 . $i . $t3;

        # Text is a single sentence
        is( join( '||', @{ $lang->get_sentences( $test_string ) } ), $test_string, "sentence_split" );
    }

    #
    # Sentence tokenizer: test 2
    #
    my @punctuation2 = ( "\x{ff0c}", "\x{ff1a}", "\x{2026}", "\x{ff01}", "\x{ff1f}", "\x{3001}", "\x{ff1b}", "\x{3002}" );
    foreach my $i ( @punctuation1 )
    {
        my $test_string = $t2 . $i . $t3;

        # Text is a single sentence
        is( join( '||', @{ $lang->get_sentences( $test_string ) } ), $test_string, "sentence_split" );
    }
}

sub test_tokenize()
{
    my $lang = MediaWords::Languages::zh->new();

    #
    # Word tokenizer: test 1
    #
    my $test_string = '主任强调指出错误的地方。';
    my $expected_words = [ '主任', '强调', '指出', '错误', '的', '地方' ];

    {
        is( join( '||', @{ $lang->tokenize( $test_string ) } ), join( '||', @{ $expected_words } ), "word_split" );
    }
}

sub main()
{
    # Test::More UTF-8 output
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_get_sentences();
    test_tokenize();
}

main();
