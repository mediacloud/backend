package MediaWords::DBI::Media;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;
use warnings;

use Encode;

use Data::Dumper;


# find the media source by the url or the url with/without the trailing slash
sub find_medium_by_url
{
    my ( $dbis, $url ) = @_;

    my $base_url = $url;

    $base_url =~ m~^([a-z]*)://~;
    my $protocol = $1 || 'http';

    $base_url =~ s~^([a-z]+://)?(www\.)?~~;
    $base_url =~ s~/$~~;

    my $url_permutations =
      [ "$protocol://$base_url", "$protocol://www.$base_url", "$protocol://$base_url/", "$protocol://www.$base_url/" ];

    my $medium =
      $dbis->query( "select * from media where url in (?, ?, ?, ?) order by length(url) desc", @{ $url_permutations } )
      ->hash;

    return $medium;
}


1;
