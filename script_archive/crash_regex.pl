#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use utf8;

use Data::Dumper;
use Perl6::Say;
use Encode;
use MIME::Base64;
use Lingua::EN::Sentence::MediaWords;
use utf8;

use Lingua::Stem;
use Lingua::Stem::Ru;
use Data::Dumper;
use Perl6::Say;
use Lingua::EN::Sentence::MediaWords;
use Lingua::Stem::Snowball;
use MediaWords::Util::Stemmer;
use Data::Dumper;
use Encode;
use MIME::Base64;
use Regexp::Optimizer;

sub hang_regex
{
    my ( $text ) = @_;

    print "starting _apply_dangerous_regex\n";
    eval {
      #utf8::upgrade( $text );
      print Dumper( $text );
      print "\n";

    };

    my $temp = $text;
    #print Dumper( $temp );
    #utf8::upgrade( $temp );
    my $temp_base64 = encode_base64( encode("UTF-8", $temp ) );

    eval {
      print "Based64 encoded: '$temp_base64'";
      print "\n";
    };

    utf8::upgrade( $temp_base64 );

    print Dumper ($temp_base64);
    print "\n";

    #$text =~ s/([^-\w]\w[\.!?])\001/$1/sgo; 

    print "starting _apply_dangerous_regex part 1\n";

    $text =~ s/([^-\w]\w\.)\001/$1/sgo; 

    print "starting _apply_dangerous_regex part 2\n";
    $text =~ s/([^-\w]\w\!)\001/$1/sgo; 
    print "starting _apply_dangerous_regex part 3\n";
    $text =~ s/([^-\w]\w\?)\001/$1/sgo; 
    print "Finished _apply_dangerous_regex\n\n";

    return $text;
}

my $VAR2 = '0LrQsNC8LgE=';

my $var2_base64_decoded = decode ( "utf8", decode_base64 ( $VAR2 ) );

say STDERR Dumper( $VAR2);
say STDERR Dumper( $var2_base64_decoded );

hang_regex ( $var2_base64_decoded );

Lingua::EN::Sentence::MediaWords::_apply_dangerous_regex ( $var2_base64_decoded );

say STDERR "Survived dangerous regular expression";
