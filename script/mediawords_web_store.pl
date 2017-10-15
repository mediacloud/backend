#!/usr/bin/env perl

# accept a list of urls and file names on standard input and get those in parallel.  for each url, store the
# Storable of the response in the associated file name.
#
# input format:
# <file>:<url>
# <file>:<url>
# ...
#
# This is executed by MediaWords::Util::Web to avoid forking the existing, big process which may muck up database
# handles and have other side effects

package script::mediawords_web_store;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Parallel::ForkManager;
use Storable;
use Readonly;

use MediaWords::Util::URL;
use MediaWords::Util::Web;

# number of processes to run in parallel
Readonly my $DEFAULT_NUM_PARALLEL => 10;

# timeout any given request after this many seconds
Readonly my $DEFAULT_TIMEOUT => 90;

# number of seconds to wait before sending a new request to a given domain
Readonly my $DEFAULT_PER_DOMAIN_TIMEOUT => 1;

sub get_request_domain
{
    my ( $request ) = @_;

    $request->{ url } =~ m~https?://([^/]*)~ || return $request;

    my $host = $1;

    my $name_parts = [ split( /\./, $host ) ];

    my $n = scalar( @{ $name_parts } ) - 1;

    my $domain;

    # for country domains, use last three parts of name
    if ( $host =~ /\...$/ )
    {
        $domain = join( ".", ( $name_parts->[ $n - 2 ], $name_parts->[ $n - 1 ], $name_parts->[ $n ] ) );
    }
    elsif ( $host =~ /localhost|blogspot.com|wordpress.com/ )
    {
        $domain = $request->{ url };
    }
    else
    {
        $domain = join( ".", $name_parts->[ $n - 1 ], $name_parts->[ $n ] );
    }

    return lc( $domain );
}

# schedule the requests by adding a { time => $time } field to each request
# to make sure we obey the $per_domain_timeout.  sort requests by ascending time.
sub get_scheduled_requests
{
    my ( $requests, $per_domain_timeout ) = @_;

    my $domain_requests = {};

    for my $request ( @{ $requests } )
    {
        my $domain = get_request_domain( $request );
        push( @{ $domain_requests->{ $domain } }, $request );
    }

    my $scheduled_requests = [];

    while ( my ( $domain, $domain_requests ) = each( %{ $domain_requests } ) )
    {
        my $time = 0;
        for my $domain_request ( @{ $domain_requests } )
        {
            $domain_request->{ time } = $time;
            push( @{ $scheduled_requests }, $domain_request );
            $time += $per_domain_timeout unless ( $time % 5 );
        }
    }

    return [ sort { $a->{ time } <=> $b->{ time } } @{ $scheduled_requests } ];
}

sub main
{
    my $requests;

    while ( my $line = <STDIN> )
    {
        chomp( $line );
        if ( $line =~ /^([^:]*):(.*)/ )
        {
            push( @{ $requests }, { file => $1, url => $2 } );
        }
        else
        {
            WARN "Unable to parse line: $line";
        }

    }

    if ( !$requests || !scalar( @{ $requests } ) )
    {
        return;
    }

    my $config = MediaWords::Util::Config::get_config;

    my $num_parallel       = $config->{ mediawords }->{ web_store_num_parallel } || $DEFAULT_NUM_PARALLEL;
    my $timeout            = $config->{ mediawords }->{ web_store_timeout };
    my $per_domain_timeout = $config->{ mediawords }->{ web_store_per_domain_timeout };

    $timeout            = $DEFAULT_TIMEOUT            unless ( defined( $timeout ) );
    $per_domain_timeout = $DEFAULT_PER_DOMAIN_TIMEOUT unless ( defined( $per_domain_timeout ) );

    DEBUG "per_domain_timeout: $per_domain_timeout";

    my $pm = new Parallel::ForkManager( $num_parallel );

    my $ua = MediaWords::Util::Web::UserAgent->new();

    $requests = get_scheduled_requests( $requests, $per_domain_timeout );
    my $start_time = time;

    my $request_stack = [ sort { $b->{ time } <=> $a->{ time } } @{ $requests } ];

    my $i     = 0;
    my $total = scalar( @{ $requests } );

    my $request_blocks = [];
    while ( @{ $request_stack } )
    {
        my $block_i = scalar( @{ $request_stack } ) % $num_parallel;
        push( @{ $request_blocks->[ $block_i ] }, pop( @{ $request_stack } ) );
    }

    for my $request_block ( @{ $request_blocks } )
    {
        $pm->start and next;

        my $block_size = $request_block ? scalar( @{ $request_block } ) : 0;

        for my $request ( @{ $request_block } )
        {
            my $time_increment = time - $start_time;

            if ( $time_increment < $request->{ time } )
            {
                my $sleep_time = $request->{ time } - $time_increment;
                sleep( $sleep_time );
            }

            alarm( $timeout );

            $i++;
            INFO "fetch [$i/$block_size/$total] : $request->{ url }";

            my $response = $ua->get( $request->{ url } );

            $response = MediaWords::Util::URL::get_meta_redirect_response( $response, $request->{ url } );

            INFO "got [$i/$block_size/$total]: $request->{ url } (" . ref( $response ) . ")";

            Storable::store( $response, $request->{ file } );

            my $stored_response = Storable::retrieve( $request->{ file } );
            if ( !$stored_response || ( ref( $stored_response ) ne ref( $response ) ) )
            {
                INFO "failed to store response for file $request->{ file }";
                INFO "request: " . $request->as_string;
                INFO "response: " . $response->as_string;
            }

            alarm( 0 );
        }

        $pm->finish;
    }

    $pm->wait_all_children;
}

main();
