package MediaWords::Util::Process;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.util.process' );

my $child_pids = [];

our @ISA    = qw(Exporter);
our @EXPORT = qw(mc_fork fatal_error);

sub mc_fork
{
    my $pid = fork();

    if ( $pid != 0 )
    {
        my @arr = @{ $child_pids };
        push( @{ $child_pids }, $pid );
        $SIG{ TERM } = \&_handle_sig;
    }
    else
    {
        if ( defined( $SIG{ TERM } ) )
        {
            undef( $SIG{ TERM } );
        }

        $child_pids = [];
    }

    return $pid;
}

sub _handle_sig
{
    INFO "caught sig";
    foreach my $pid ( @$child_pids )
    {
        INFO "killing $pid";
        kill( "TERM", $pid );
    }

    if ( scalar( @$child_pids ) > 0 )
    {
        INFO "waiting for children";
        while ( wait > -1 )
        {

        }
    }

    INFO "exiting";
    exit;
}

1;
