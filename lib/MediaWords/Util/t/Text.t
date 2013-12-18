#
# test MediaWords::Util::Text
#

use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 7 + 2;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::Text' );
}

sub test_get_similarity_score()
{
    my $text_1;
    my $text_2;
    my $score;

    # Identical texts
    $text_1 = 'The quick brown fox jumps over the lazy dog.';
    $text_2 = $text_1;
    $score  = MediaWords::Util::Text::get_similarity_score( $text_1, $text_2, 'en' );
    is( $score, 1, 'identical texts' );

    # Texts that differ 100%
    $text_1 = 'One two three four five six seven eight nine ten.';
    $text_2 = 'Eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty.';
    $score  = MediaWords::Util::Text::get_similarity_score( $text_1, $text_2, 'en' );
    is( $score, 0, '100% different texts' );

    # Overlapping texts (text #1 is a part of text #2)
    $text_1 = <<EOF;
One morning, when Gregor Samsa woke from troubled dreams, he found himself
transformed in his bed into a horrible vermin. He lay on his armour-like back,
and if he lifted his head a little he could see his brown belly, slightly domed
and divided by arches into stiff sections. The bedding was hardly able to cover
it and seemed ready to slide off any moment. His many legs, pitifully thin
compared with the size of the rest of him, waved about helplessly as he looked.
EOF

    $text_2 = <<EOF;
One morning, when Gregor Samsa woke from troubled dreams, he found himself
transformed in his bed into a horrible vermin. He lay on his armour-like back,
and if he lifted his head a little he could see his brown belly, slightly domed
and divided by arches into stiff sections. The bedding was hardly able to cover
it and seemed ready to slide off any moment. His many legs, pitifully thin
compared with the size of the rest of him, waved about helplessly as he looked.

"What's happened to me?" he thought. It wasn't a dream. His room, a proper
human room although a little too small, lay peacefully between its four
familiar walls. A collection of textile samples lay spread out on the table -
Samsa was a travelling salesman - and above it there hung a picture that he had
recently cut out of an illustrated magazine and housed in a nice, gilded frame.
It showed a lady fitted out with a fur hat and fur boa who sat upright, raising
a heavy fur muff that covered the whole of her lower arm towards the viewer.
EOF
    $score = MediaWords::Util::Text::get_similarity_score( $text_1, $text_2, 'en' );

    # Text::Similarity::Overlaps score is 0.625
    cmp_ok( $score, '>=', 0.6, 'Overlapping texts #1' );
    cmp_ok( $score, '<=', 0.7, 'Overlapping texts #2' );

    # Same texts but swapped
    my $temp = $text_1;
    $text_1 = $text_2;
    $text_2 = $temp;
    my $score_swapped = MediaWords::Util::Text::get_similarity_score( $text_1, $text_2, 'en' );
    is( $score, $score_swapped, 'Swapped texts' );

    # Non-English, non-ASCII text
    $text_1 = <<EOF;
Все счастливые семьи похожи друг на друга, каждая несчастливая семья
несчастлива по-своему.

Все смешалось в доме Облонских. Жена узнала, что муж был в связи с бывшею в их
доме француженкою-гувернанткой, и объявила мужу, что не может жить с ним в
одном доме. Положение это продолжалось уже третий день и мучительно
чувствовалось и самими супругами, и всеми членами семьи, и домочадцами. Все
члены семьи и домочадцы чувствовали, что нет смысла в их сожительстве и что на
каждом постоялом дворе случайно сошедшиеся люди более связаны между собой, чем
они, члены семьи и домочадцы Облонских. Жена не выходила из своих комнат, мужа
третий день не было дома. Дети бегали по всему дому, как потерянные; англичанка
поссорилась с экономкой и написала записку приятельнице, прося приискать ей
новое место; повар ушел вчера со двора, во время самого обеда; черная кухарка и
кучер просили расчета.
EOF
    $text_2 = <<EOF;
На третий день после ссоры князь Степан Аркадьич Облонский — Стива, как его
звали в свете, — в обычный час, то есть в восемь часов утра, проснулся не в
спальне жены, а в своем кабинете, на сафьянном диване. Он повернул свое полное,
выхоленное тело на пружинах дивана, как бы желая опять заснуть надолго, с
другой стороны крепко обнял подушку и прижался к ней щекой; но вдруг вскочил,
сел на диван и открыл глаза.

«Да, да, как это было? — думал он, вспоминая сон. — Да, как это было? Да!
Алабин давал обед в Дармштадте; нет, не в Дармштадте, а что-то американское.
Да, но там Дармштадт был в Америке. Да, Алабин давал обед на стеклянных столах,
да, — и столы пели: Il mio tesoro 1 и не Il mio tesoro, а что-то лучше, и
какие-то маленькие графинчики, и они же женщины», — вспоминал он.
EOF
    $score = MediaWords::Util::Text::get_similarity_score( $text_1, $text_2, 'ru' );

    # Text::Similarity::Overlaps score is 0.177
    cmp_ok( $score, '>=', 0,   'Non-English, non-ASCII texts #1' );
    cmp_ok( $score, '<=', 0.2, 'Non-English, non-ASCII texts #2' );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_get_similarity_score();
}

main();
