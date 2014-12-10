#!/usr/bin/env perl

# create media_tag_tag_counts table by querying the database tags / feeds / stories

use strict;

use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use LWP::UserAgent;

use MediaWords::Util::Config;

sub main
{
    my ( $url ) = @ARGV;

    die( "usage: $0 < url >" ) unless ( $url );

    my $ua     = LWP::UserAgent->new();
    my $config = MediaWords::Util::Config::get_config;

    $ua->from( $config->{ mediawords }->{ owner } );
    $ua->agent( $config->{ mediawords }->{ user_agent } );
    $ua->cookie_jar( {} );

    $ua->timeout( 20 );
    $ua->max_size( 1024 * 1024 );
    $ua->max_redirect( 15 );
    $ua->env_proxy;

    my $response = $ua->get( $url );

    print $response->as_string;
}

main();
