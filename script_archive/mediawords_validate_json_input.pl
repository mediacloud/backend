#!/usr/bin/perl

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Date::Parse;
use HTTP::Request;
use LWP::UserAgent;
use Text::CSV_XS;
use Text::Trim;
use JSON;
use Data::Dumper;
use utf8;

my $test_scalar = [ {"term" => "ekponé"}];

sub main
{
   my $json;
    while(<>)
      {
	$json .= $_;
      }

   # print Dumper($test_scalar);

   # print Dumper(encode_json($test_scalar));
   # print Dumper(decode_json(encode_json($test_scalar)));

   # print Dumper( $json);
     my $words = decode_json( $json );
     my $words = from_json( $json );

   my $reencoded = encode_json( $words );

   my $redecoded = decode_json( $reencoded );
    
   # print Dumper( $words);
}

main();
