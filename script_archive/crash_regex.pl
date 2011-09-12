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

sub hang_regex
{
    my ( $text ) = @_;

    $text =~ s/([^-\w]\w\.)\001/$1/sgo; 

    return $text;
}

my $VAR2 = '0LrQsNC8LgE=';

my $var2_base64_decoded = decode ( "utf8", decode_base64 ( $VAR2 ) );

say STDERR Dumper( $VAR2);
say STDERR Dumper( $var2_base64_decoded );

hang_regex ( $var2_base64_decoded );

say STDERR "Survived dangerous regular expression";
