package MediaWords::Util::Process;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;
use strict;
use warnings;

use Data::Dumper;
use Carp qw/confess cluck/;

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

    if ( scalar( @$child_pids ) > 0 )
    {
        say STDERR "waiting for children";
        while ( wait > -1 )
        {

        }
    }

    say STDERR "exiting";
    exit;
}

# Sometimes when an error happens, we can't use die() because it would get
# caught in eval{}.
#
# We don't always want that: for example, if crawler dies because of
# misconfiguration in mediawords.yml, crawler's errors would get logged into
# "downloads" table as if the error happened because of a valid reason.
#
# In those cases, we go straight to exit(1) using this helper subroutine.
sub fatal_error($)
{
    my $error_message = shift;

    cluck $error_message;
    exit 1;
}

1;
