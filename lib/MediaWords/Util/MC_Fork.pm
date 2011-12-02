package MediaWords::Util::MC_Fork;
use MediaWords::CommonLibs;


use Moose;
use strict;
use warnings;

use Perl6::Say;
use Data::Dumper;

my $child_pids = [];

our @ISA    = qw(Exporter);
our @EXPORT = qw(mc_fork);

sub mc_fork
{
    my $pid = fork();

    if ( $pid != 0 )
    {
        my @arr = @{ $child_pids };
        push( @{ $child_pids }, $pid );
    }
    else
    {
        if ( defined( $SIG { TERM } ) )
	{
	    undef( $SIG{ TERM } );
	}

        $child_pids = [];
    }

    return $pid;
}

sub dump_child_pids
{
    say STDERR "Dumping child PIDS";
    say STDERR join "\n", @$child_pids;
}

sub _handle_sig
{
    say STDERR "caught sig";
    foreach my $pid ( @$child_pids )
    {
        say STDERR "killing $pid";
        kill( "TERM", $pid );
    }

    #say STDERR "waiting for child";
    while ( wait > -1 )
    {

    }

    exit;
}

$SIG{ TERM } = \&_handle_sig;

1;
