package MediaWords::DBI::Media;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;
use warnings;

use Encode;

use Regexp::Common qw /URI/;

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

# given a newline separated list of media urls, return a list of hashes in the form of
# { medium => $medium_hash, url => $url, tags_string => $tags_string, message => $error_message }
# the $medium_hash is the existing media source with the given url, or undef if no existing media source is found.
# the tags_string is everything after a space on a line, to be used to add tags to the media source later.
sub find_media_from_urls
{
    my ( $dbis, $urls_string ) = @_;

    my $url_media = [];

    my $urls = [ split( "\n", $urls_string ) ];

    for my $tagged_url ( @{ $urls } )
    {
        my $medium;

        my ( $url, $tags_string ) = ( $tagged_url =~ /^\r*\s*([^\s]*)(?:\s+(.*))?/ );

        if ( $url !~ m~^[a-z]+://~ )
        {
            $url = "http://$url";
        }

        $medium->{ url }         = $url;
        $medium->{ tags_string } = $tags_string;

        if ( $url !~ /$RE{URI}/ )
        {
            $medium->{ message } = "'$url' is not a valid url";
        }

        $medium->{ medium } = MediaWords::DBI::Media::find_medium_by_url( $dbis, $url );

        push( @{ $url_media }, $medium );
    }

    return $url_media;
}

1;
