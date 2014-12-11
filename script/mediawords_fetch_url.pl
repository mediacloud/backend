#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Util::Web;

sub main
{
    my ( $url ) = @ARGV;

    die( "usage: $0 < url >" ) unless ( $url );

    my $ua = MediaWords::Util::Web::UserAgent;

    $ua->cookie_jar( {} );

    my $response = $ua->get( $url );

    print $response->as_string;
}

main();
