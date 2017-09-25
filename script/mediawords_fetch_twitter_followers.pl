#!/usr/bin/env perl

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Net::Twitter;

use MediaWords::Util::Config;

sub main
{
    my ( $user ) = @ARGV;

    die( "$@ <user name>" ) unless ( $user );

    my $config = MediaWords::Util::Config::get_config;

    my $twitter = Net::Twitter->new(
        traits              => [ qw/API::RESTv1_1/ ],
        ssl                 => 1,
        consumer_key        => $config->{ twitter }->{ consumer_key },
        consumer_secret     => $config->{ twitter }->{ consumer_secret },
        access_token        => $config->{ twitter }->{ access_token },
        access_token_secret => $config->{ twitter }->{ access_token_secret },
    );

    my $num_ids = 0;
    my $cursor  = -1;
    my $r;
    while ( $cursor )
    {
        DEBUG( "fetching ( $num_ids / $cursor ) ..." );

        $r = eval { $twitter->followers_ids( { screen_name => $user, cursor => $cursor } ) };
        if ( $@ && ( $@ =~ /Rate limit exceeded/ ) )
        {
            DEBUG( "waiting for rate limit ..." );
            sleep( 30 );
            next;
        }

        print( join( "\n", @{ $r->{ ids } } ) . "\n" );

        $cursor = $r->{ next_cursor };
        $num_ids += scalar( @{ $r->{ ids } } );
    }
}

main();
