new#!/usr/bin/env perl

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

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Parallel::ForkManager;
use Storable;

use MediaWords::Util::URL;
use MediaWords::Util::Web;

# number of processes to run in parallel
use constant DEFAULT_NUM_PARALLEL => 10;

# timeout any given request after this many seconds
use constant DEFAULT_TIMEOUT => 90;

# number of seconds to wait before sending a new request to a given domain
use constant DEFAULT_PER_DOMAIN_TIMEOUT => 1;

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

# given the response and request, parse the content for a meta refresh url and return if present.
# otherwise, return undef
sub get_meta_refresh_url
{
    my ( $response, $request ) = @_;

    return undef unless ( $response->is_success );

    MediaWords::Util::URL::meta_refresh_url_from_html( $response->decoded_content, $request->{ url } );
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
            warn( "Unable to parse line: $line" );
        }

    }

    if ( !$requests || !scalar( @{ $requests } ) )
    {
        return;
    }

    my $config = MediaWords::Util::Config::get_config;

    my $num_parallel       = $config->{ mediawords }->{ web_store_num_parallel } || DEFAULT_NUM_PARALLEL;
    my $timeout            = $config->{ mediawords }->{ web_store_timeout };
    my $per_domain_timeout = $config->{ mediawords }->{ web_store_per_domain_timeout };

    $timeout            = DEFAULT_TIMEOUT            unless ( defined( $timeout ) );
    $per_domain_timeout = DEFAULT_PER_DOMAIN_TIMEOUT unless ( defined( $per_domain_timeout ) );

    my $pm = new Parallel::ForkManager( $num_parallel );

    my $ua = MediaWords::Util::Web::UserAgent();

    $requests = get_scheduled_requests( $requests, $per_domain_timeout );
    my $start_time = time;

    my $i     = 0;
    my $total = scalar( @{ $requests } );

    for my $request ( @{ $requests } )
    {
        my $time_increment = time - $start_time;
        $i++;

        if ( $time_increment < $request->{ time } )
        {
            sleep( $request->{ time } - $time_increment );
        }

        alarm( $timeout );
        $pm->start and next;

        print STDERR "fetch [$i/$total] : $request->{ url }\n";

        my $response = $ua->get( $request->{ url } );

        for ( my $i = 0; ( $i < 10 ) && ( my $url = get_meta_refresh_url( $response, $request ) ); $i++ )
        {
            $response = $ua->get( $url );
        }

        print STDERR "got [$i/$total]: $request->{ url }\n";

        Storable::store( $response, $request->{ file } );

        $pm->finish;

        alarm( 0 );
    }

    $pm->wait_all_children;
}

main();
