#
# Test MediaWords::Util::Text::get_similarity_score() by comparing it to Text::Similarity::Overlaps
#

use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Readonly;
use Test::More tests => 25;

# Run the comparison multiple times so that the performance difference is more obvious
Readonly my $TEST_ITERATIONS => 100;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'Time::HiRes' );
    use_ok( 'MediaWords::Util::Text' );
    use_ok( 'Text::Similarity::Overlaps' );
}

# Helper to compare results from Text::Similarity::Overlaps and Media Cloud's implementation
sub _compare_similarity_score($$$$$)
{
    my ( $identifier, $text_1, $text_2, $language, $score_epsilon ) = @_;

    my $sim = Text::Similarity::Overlaps->new( { normalize => 1, verbose => 0 } );

    my ( $expected_score, $actual_score );
    my ( $time_before,    $time_after );

    # print STDERR "\n\n";
    # print STDERR "Identifier: $identifier\n";

    # Text::Similarity::Overlaps
    $time_before = Time::HiRes::time();
    for ( my $x = 0 ; $x < $TEST_ITERATIONS ; ++$x )
    {
        $expected_score = $sim->getSimilarityStrings( $text_1, $text_2 );
    }
    $time_after = Time::HiRes::time();

    # print STDERR "Text::Similarity::Overlaps:\n";
    # printf STDERR "\tScore: %2.6f\n", $expected_score;
    # printf STDERR "\tTime: %2.6f\n", ( $time_after - $time_before );

    # Media Cloud's implementation
    $time_before = Time::HiRes::time();
    for ( my $x = 0 ; $x < $TEST_ITERATIONS ; ++$x )
    {
        $actual_score = MediaWords::Util::Text::get_similarity_score( $text_1, $text_2, $language );
    }
    $time_after = Time::HiRes::time();

    # print STDERR "MediaWords::Util::Text::get_similarity_score():\n";
    # printf STDERR "\tScore: %2.6f\n", $actual_score;
    # printf STDERR "\tTime: %2.6f\n", ( $time_after - $time_before );

    cmp_ok( abs( $expected_score - $actual_score ), '<=', $score_epsilon, "$identifier: core is below the threshold" );
}

sub test_get_similarity_score()
{
    my $text_1;
    my $text_2;
    my $score;

    # Identical texts
    $text_1 = 'The quick brown fox jumps over the lazy dog.';
    $text_2 = $text_1;
    _compare_similarity_score( '100% identical texts', $text_1, $text_2, 'en', 0 );    # no error margin in expected score

    # Texts that differ 100%
    $text_1 = 'One two three four five six seven eight nine ten.';
    $text_2 = 'Eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty.';
    _compare_similarity_score( '100% different texts', $text_1, $text_2, 'en', 0 );    # no error margin in expected score

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
    _compare_similarity_score( 'overlapping texts', $text_1, $text_2, 'en', 0.1 );

    # Same texts but swapped
    _compare_similarity_score( 'overlapping texts (swapped)', $text_2, $text_1, 'en', 0.1 );

    # Non-English, non-ASCII text (excerpt from Tolstoy's "Anna Karenina")
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
    _compare_similarity_score( 'non-English, non-ASCII texts', $text_2, $text_1, 'ru', 0.15 );

    # English RSS description and body from "Global Voices" article
    # (http://globalvoicesonline.org/?p=454555)
    $text_1 = <<EOF;
According to a recent opinion poll, three candidates are tied for first place
in Sunday's presidential election in Costa Rica.
EOF
    $text_2 = <<EOF;
Costa Rica is just a day away from electing a new president, the culmination of
one of the hardest-fought electoral races in the country's history. The race is
still too close to call, with candidates on the left, centre, and right running
neck and neck. It is, without a doubt, democracy in action.

According to the latest opinion poll conducted by Unimer for the La Nación
newspaper, there are three candidates tied for first place: José Maria Villalta
of the leftist Frente Amplio [en], Johnny Araya of the more moderate Liberación
Nacional [en] and Otto Guevara of the right wing Movimiento Libertario [en].

The data provided by the marketing research firm on January 16, 2014, shows José
María Villalta's support at 22.2%, Johnny Araya with 20.3% and Otto Guevara at
20.2%. Given a margin of error of 2.2 percentage points, this is considered—in
technical terms—a tie. Of the top five candidates, based on popular support, the
next two rank significantly lower than the leaders, with Luis Guillermo Solís
(Partido Acción Ciudadana) [en] at 5.5% and Rodolfo Piza (Partido Unidad Social
Cristiana) [en] at 3.6%.

Clearly these numbers set off alarm bells in the campaign headquarters of the
governing Liberación Nacional party, which has always enjoyed a solid lead with
strong numbers. The possibility that there might be a second round had not even
occurred to them.

On the other hand, another poll by Cid Gallup for Noticias Repretel, published
on January 28, shows Johnny Araya with 35.6%, followed by José Maria Villalta
with 21%, Otto Guevara in third place at 17.6%, Luis Guillermo Solis in fourth
with 15.6%, and Rodolfo Piza with 6.5% .

These elections have been full of contrasts. Take the case of the Frente Amplio
party, labelled left wing and traditionally a minor player, which this time
garnered the kind of support even its most optimistic followers would not have
predicted; or the case of Luis Guillermo Solis, who has also gained ground in
the last two months, with support coming mainly from younger voters; finally,
the current situation facing the government has greatly affected its candidate
Johny Araya, whose approval rating in the polls has waned, although it now
remains steady.

There is little doubt that these elections will define a generation of Costa
Ricans and determine the future of the country in a dramatic way.

Juan Carlos Hidalgo, an analyst covering Latin American politics for the Cato
Institute, says:

La de este domingo es quizás la más importante que hemos enfrentado en una
generación: el 2 de febrero tenemos ante nosotros una clara disyuntiva: seguimos
igual, retrocedemos o avanzamos.

Las redes sociales han servido de caja de resonancia en la discusión política
cotidiana. Antes, discutíamos entre familia y amigos. Hoy, nos vemos enfrascados
en interminables discusiones con desconocidos sobre una amplia gama de temas.

This Sunday's [election] is perhaps the most important we have faced in a
generation: on February 2, we will have a clear choice to make: continue as we
have, go backwards or move forward.

Social networks have been a sounding board in the daily political discussions.
Before, we talked among friends and family. Today, we are caught up in
interminable discussions with strangers about a whole range of topics.

The drop in popularity of current President Laura Chinchilla's government will
surely affect the outcome of the election—and mainly her own party, Liberación
Nacional. The slogan of almost all the ads run by the other political parties
emphasizes the need for change in Costa Rica.

It is also clear that, like never before in the country's history, people are
informed, thanks to social media and digital access to the candidates’ political
platforms. While both things existed before, they have become tools that the
political parties increasingly know how to use. These elections will definitely
signal a before-and-after divide in the way politics in the country is
conducted.
EOF
    _compare_similarity_score( 'English RSS description and body (Global Voices)', $text_2, $text_1, 'en', 0.005 );

    # Non-English (Italian) RSS description and body from "Global Voices" article
    # (http://it.globalvoicesonline.org/?p=90107)
    $text_1 = <<EOF;
Durante il Capodanno Cinese è tradizione regalare Buste Rosse con i soldi.
Anche su WeChat e altri social cinesi è stata creata l'analoga app virtuale.
EOF
    $text_2 = <<EOF;
In Cina è tradizione inviare buste rosse come regalo durante la festa per il
Capodanno Lunare. Quest'anno la tradizione passa al formato digitale, sulla
piattaforma di social media più utilizzata in Cina. Ora, infatti, le persone
hanno la possibilità di inviare le buste rosse attraverso la popolare
applicazione di messaggistica mobile WeChat.

La busta rossa è un regalo in denaro che viene donato in occasioni speciali come
i matrimoni e il Capodanno Cinese. Il colore rosso della busta è simbolo di buon
augurio e si ritiene tenga lontani gli spiriti maligni.

Con l'avvicinarsi del Capodanno Lunare, il colosso del web cinese Tencent, ha
introdotto una nuova funzione per i suoi 600 milioni di utenti su WeChat: “Busta
Rossa”, con la quale gli utenti in tutto il mondo posso inviare e ricevere buste
rosse virtuali collegate al loro conto bancario.

Screenshot of the "red envelope" feature on WeChat  Fermo immagine della
funzione Busta Rossa su WeChat È facile da usare. Gli utenti possono inviare una
busta a singoli amici su WeChat o addirittura creare un gruppo, inviare una
busta e il primo membro che la apre riceve i soldi. L'utente può anche destinare
in modo casuale una certa quantità di denaro a un gruppo di amici.

WeChat ha rimpiazzato Sina Weibo comepiattaforma di social media più popolare
nel 2013. Con i suoi circa 78 milioni di utenti fuori dalla Cina, l'applicazione
ha anche avuto una crescita significativa nell’ anno passato.

La nuova funzione “busta rossa” dovrebbe portare a un aumento del numero di
utenti di WeChat ed estendere la sua funzione di pagamento online.

Quest'idea non riguarda solamente WeChat. Sia Sina Weibo che Alipay hanno
introdotto questa funzione. Durante la Festa di Primavera dello scorso anno,
sono stati inviati l'equivalente di 1,64 milioni di yuan (circa 200.000 euro) in
buste rosse virtuali su Alipay. Grazie alla componente social di WeChat e
all'aggiunta di elementi interattvi e divertenti, la funzione probabilmente
acquisterà maggiore popolarità quest'anno.
EOF
    _compare_similarity_score( 'Italian RSS description and body (Global Voices)', $text_2, $text_1, 'it', 0.04 );
}

sub test_encode_decode_utf8()
{
    Readonly my @test_strings => (

        # ASCII
        "Media Cloud\r\nMedia Cloud\nMedia Cloud\r\n",

        # UTF-8
        "Media Cloud\r\nąčęėįšųūž\n您好\r\n",

        # Empty string
        "",

        # Invalid UTF-8 sequences
        "\xc3\x28",
        "\xa0\xa1",
        "\xe2\x28\xa1",
        "\xe2\x82\x28",
        "\xf0\x28\x8c\xbc",
        "\xf0\x90\x28\xbc",
        "\xf0\x28\x8c\x28",
        "\xf8\xa1\xa1\xa1\xa1",
        "\xfc\xa1\xa1\xa1\xa1\xa1",

    );

    foreach my $test_string ( @test_strings )
    {
        my $encoded_string = MediaWords::Util::Text::encode_to_utf8( $test_string );
        my $decoded_string = MediaWords::Util::Text::decode_from_utf8( $encoded_string );
        is( $decoded_string, $test_string, "Encoded+decoded string matches" );
    }
}

sub test_is_valid_utf8()
{
    ok( MediaWords::Util::Text::is_valid_utf8( 'pnoןɔ ɐıpǝɯ' ), 'Valid UTF-8' );
    ok( !MediaWords::Util::Text::is_valid_utf8( "\xc3\x28" ),         'Invalid UTF-8' );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_get_similarity_score();
    test_encode_decode_utf8();
    test_is_valid_utf8();
}

main();
