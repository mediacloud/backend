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

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Parallel::ForkManager;
use Storable;

use MediaWords::Util::Web;

use constant NUM_PARALLEL      => 10;
use constant TIMEOUT           => 20;

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

    if ( !$requests || !@{ $requests } )
    {
        return;
    }

    my $pm = new Parallel::ForkManager( NUM_PARALLEL );

    my $ua = MediaWords::Util::Web::UserAgent();

    my $i     = 0;
    my $total = scalar( @{ $requests } );

    $SIG{ ALRM } = sub { die( "web request timed out" ); };

    for my $request ( @{ $requests } )
    {
        $i++;

        alarm( TIMEOUT );
        $pm->start and next;

        print STDERR "fetch [$i/$total] : $request->{ url }\n";

        my $response = $ua->get( $request->{ url } );

        print STDERR "got [$i/$total]: $request->{ url }\n";

        Storable::store( $response, $request->{ file } );

        $pm->finish;

        alarm( 0 );
    }

    $pm->wait_all_children;
}

main();
