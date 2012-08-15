#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More tests => 14 + 1;

use_ok( 'MediaWords::Util::StopWords' );
use MediaWords::Util::StopWords;

use Data::Dumper;
use utf8;

#<<<
ok(MediaWords::Util::StopWords::get_tiny_stop_word_lookup, 'get_tiny_stop_word_lookup');

#say Dumper (MediaWords::Util::StopWords::get_tiny_stop_word_lookup);
my $tiny_stop_words = MediaWords::Util::StopWords::get_tiny_stop_word_lookup;
ok(scalar(keys(%{$tiny_stop_words})) >= 174, "stop words count is correct");

is ($tiny_stop_words->{the}, 1);
is ($tiny_stop_words->{a}, 1);
is ($tiny_stop_words->{is}, 1);
is ($tiny_stop_words->{и}, 1, "russian test");
is ($tiny_stop_words->{я}, 1, "russian test");

my $tiny_stemmed_stop_words = MediaWords::Util::StopWords::get_tiny_stop_stem_lookup;

ok(scalar(keys(%{$tiny_stemmed_stop_words})) >= 174, "stop words count is correct");
is ( $tiny_stemmed_stop_words->{a}, 1 , "Stemmed stop words" );

ok(MediaWords::Util::StopWords::get_short_stop_word_lookup, 'get_tiny_stop_word_lookup');

ok(MediaWords::Util::StopWords::get_tiny_stop_stem_lookup(), "get_tiny_stop_stem_lookup()");
ok(MediaWords::Util::StopWords::get_short_stop_stem_lookup(), 'get_short_stop_stem_lookup()');
ok(MediaWords::Util::StopWords::get_long_stop_stem_lookup(), 'get_long_stop_stem_lookup()');

#say Dumper([MediaWords::Util::StopWords::get_tiny_stop_word_lookup()]);
#say Dumper([MediaWords::Util::StopWords::get_tiny_stop_stem_lookup()]);

#>>>
