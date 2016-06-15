#!/usr/bin/perl
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
use Test::More tests => 3 + 1;
use utf8;

use MediaWords::Languages::tr;
use Data::Dumper;

sub test_get_sentences()
{
    my $test_string;
    my $expected_sentences;

    my $lang = MediaWords::Languages::tr->new();

    #
    # Simple paragraph
    #
    $test_string = <<'QUOTE';
Google, (NASDAQ: GOOG), internet araması, çevrimiçi bilgi dağıtımı, reklam teknolojileri
ve arama motorları için yatırımlar yapan çok uluslu Amerikan anonim şirketidir. İnternet
tabanlı hizmet ve ürünler geliştirir, ek olarak bunlara ev sahipliği yapar. Kârının büyük
kısmını AdWords programı aracılığıyla reklamlardan elde etmektedir. Şirket, Larry Page ve
Sergey Brin tarafından, Stanford Üniversitesi'nde doktora öğrencisi oldukları sırada
kurulmuştur. İkili, sık sık "Google Guys" olarak anılmaktadır. Google, ilk olarak, 4
Eylül 1998 tarihinde özel bir şirket olarak kuruldu ve 19 Ağustos 2004 tarihinde halka
arz edildi. Halka arzın gerçekleştiği dönemde, Larry Page, Sergey Brin ve Eric Schmidt,
takip eden yirmi yıl boyunca, yani 2024 yılına kadar Google'da birlikte çalışmak üzere
anlaştılar. Kuruluşundan bu yana misyonu "dünyadaki bilgiyi organize etmek ve bunu
evrensel olarak erişilebilir ve kullanılabilir hale getirmek"tir. Gayri resmi sloganı
ise, Google mühendisi Amit Patel tarafından bulunan ve Paul Buchheit tarafından
desteklenen "Don't be evil"dir.
QUOTE

    $expected_sentences = [
'Google, (NASDAQ: GOOG), internet araması, çevrimiçi bilgi dağıtımı, reklam teknolojileri ve arama motorları için yatırımlar yapan çok uluslu Amerikan anonim şirketidir.',
        'İnternet tabanlı hizmet ve ürünler geliştirir, ek olarak bunlara ev sahipliği yapar.',
        'Kârının büyük kısmını AdWords programı aracılığıyla reklamlardan elde etmektedir.',
'Şirket, Larry Page ve Sergey Brin tarafından, Stanford Üniversitesi\'nde doktora öğrencisi oldukları sırada kurulmuştur.',
        'İkili, sık sık "Google Guys" olarak anılmaktadır.',
'Google, ilk olarak, 4 Eylül 1998 tarihinde özel bir şirket olarak kuruldu ve 19 Ağustos 2004 tarihinde halka arz edildi.',
'Halka arzın gerçekleştiği dönemde, Larry Page, Sergey Brin ve Eric Schmidt, takip eden yirmi yıl boyunca, yani 2024 yılına kadar Google\'da birlikte çalışmak üzere anlaştılar.',
'Kuruluşundan bu yana misyonu "dünyadaki bilgiyi organize etmek ve bunu evrensel olarak erişilebilir ve kullanılabilir hale getirmek"tir.',
'Gayri resmi sloganı ise, Google mühendisi Amit Patel tarafından bulunan ve Paul Buchheit tarafından desteklenen "Don\'t be evil"dir.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # URLS ("google.com", "google.co.in", ...), abbreviation ("vb.")
    #
    $test_string = <<'QUOTE';
Alexa, internette en çok ziyaret edilen web sitesi olarak ABD odaklı "google.com"'u
listelemektedir, YouTube, Blogger, Orkut gibi Google'a ait diğer siteler ve çok
sayıda uluslararası Google sitesi (google.co.in, google.co.uk vb.) ise en çok
ziyaret edilen siteler arasında ilk yüz içinde yer almaktadır. Ek olarak şirket,
BrandZ marka değeri veritabanı listesinde ikinci sırada yer almaktadır. Buna karşın
Google, gizlilik, telif hakkı ve sansür gibi konularda eleştiriler almaktadır.
QUOTE

    $expected_sentences = [
'Alexa, internette en çok ziyaret edilen web sitesi olarak ABD odaklı "google.com"\'u listelemektedir, YouTube, Blogger, Orkut gibi Google\'a ait diğer siteler ve çok sayıda uluslararası Google sitesi (google.co.in, google.co.uk vb.) ise en çok ziyaret edilen siteler arasında ilk yüz içinde yer almaktadır.',
        'Ek olarak şirket, BrandZ marka değeri veritabanı listesinde ikinci sırada yer almaktadır.',
        'Buna karşın Google, gizlilik, telif hakkı ve sansür gibi konularda eleştiriler almaktadır.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
    }

    #
    # Period in the middle of the number
    #
    $test_string = <<'QUOTE';
Bir yıl önceki rakam olan 931 milyon tekil ziyaretçi sayısındaki yüzde 8.4'lük bir
artışla, 2001 Mayıs ayında; Google'nin tekil ziyaretçi sayısı ilk kez 1 milyarı buldu.
QUOTE

    $expected_sentences = [
'Bir yıl önceki rakam olan 931 milyon tekil ziyaretçi sayısındaki yüzde 8.4\'lük bir artışla, 2001 Mayıs ayında; Google\'nin tekil ziyaretçi sayısı ilk kez 1 milyarı buldu.'
    ];

    {
        is(
            join( '||', @{ $lang->get_sentences( $test_string ) } ),
            join( '||', @{ $expected_sentences } ),
            "sentence_split"
        );
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
}

main();
