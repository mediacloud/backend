#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::More tests => 7;
use utf8;

use Lingua::Stem;
use Lingua::Stem::Ru;
use Data::Dumper;
use Perl6::Say;

use Lingua::Stem::Snowball;
use MediaWords::Util::Stemmer;

# simple tokenizer
sub _tokenize
{
    my ( $s ) = @_;
    
    my $tokens = [];
    while ( $s->[0] =~ m~(\w[\w']*)~g )
    {
        push( @{ $tokens }, lc( $1 ) );
    }
    
    return $tokens;
}

#From http://en.wikipedia.org/wiki/Stemming
my $stemmer_test_text =  <<'__END_TEST_CASE__';
In linguistic morphology, stemming is the process for reducing inflected (or sometimes derived) words to their stem, base or root form – generally a written word form. The stem need not be identical to the morphological root of the word; it is usually sufficient that related words map to the same stem, even if this stem is not in itself a valid root. The algorithm has been a long-standing problem in computer science; the first paper on the subject was published in 1968. The process of stemming, often called conflation, is useful in search engines for query expansion or indexing and other natural language processing problems.
__END_TEST_CASE__

#From http://ru.wikipedia.org/
my $stemmer_test_ru_text = <<'__END_TEST_CASE__';
Сте́мминг — это процесс нахождения основы слова для заданного исходного слова. Основа слова необязательно совпадает с морфологическим корнем слова. Алгоритм стемминга представляет собой давнюю проблему в области компьютерных наук. Первый документ по этому вопросу был опубликован в 1968 году. Данный процесс применяется в поиcковых системах для обобщения поискового запроса пользователя.
__END_TEST_CASE__

 {
 my @split_words = @{ _tokenize([$stemmer_test_text] )};

 #print @split_words;
 #exit;
 my $lingua_stem = Lingua::Stem::Snowball->new(lang => 'en', encoding => 'UTF-8' );

 my $lingua_stem_result = [$lingua_stem->stem(\@split_words)];
 my $mw_stemmer = MediaWords::Util::Stemmer->new;
 my $mw_stem_result = $mw_stemmer->stem(@split_words);

 {
     is_deeply(
        $mw_stem_result,
        $lingua_stem_result,
        "Stemmer compare test"
     );
      }

 isnt($lingua_stem_result,$stemmer_test_text, "Stemmed text is changed"); 
 ok(length($lingua_stem_result) > 0, "Stemmed text is nonempty"); 
 
 }

{
ok(utf8::is_utf8($stemmer_test_ru_text), "is_utf8");

my @split_words = split /\W/, (lc $stemmer_test_ru_text);
utf8::upgrade($stemmer_test_ru_text);

my $temp = $stemmer_test_ru_text;

#$temp = lc $temp;
#say "$temp";
#say lc $temp;

@split_words =  @{_tokenize([$temp] )};

#print STDERR "stemmer_test_ru_text " . Dumper(utf8::decode($stemmer_test_ru_text));
#my @split_words = @{$tokenizer->process([$stemmer_test_ru_text ])};

#print Dumper(@split_words);
#exit;
my $lingua_stem = Lingua::Stem::Snowball->new(lang => 'ru', encoding => 'UTF-8' );
;

my $lingua_stem_result = [($lingua_stem->stem(\@split_words))];
my $mw_stemmer = MediaWords::Util::Stemmer->new;
my $mw_stem_result = $mw_stemmer->stem(@split_words);

    is_deeply(
       (join "_", @{$mw_stem_result}),
       (join "_", @{$lingua_stem_result}),
       "Stemmer compare test"
    );


    is($mw_stem_result->[0], lc $split_words[0], "first word");

    isnt(
       join ("_", @$mw_stem_result),
       join ("_", @{_tokenize([lc $stemmer_test_ru_text ])}),
       "Stemmer compare with no stemming test"
    );


}
