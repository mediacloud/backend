#TEMPORARY MIRRORING THIS MODULE WITHIN OUR SOURCE TREE NOW THAT IT HAS BEEN REMOVED FROM CPAN
# WE HOPE THAT THE MODULE WILL BE EITHER PUT BACK ON CPAN

# EVENTUALLY WE WOULD LIKE TO DROP SUPPORT FOR PERL 5.8 BUT UNFORTUNATELY OUR PRODUCTION SERVER IS ON UBUNTU 8.04 AND STILL RUNS THAT VERSION

{
    use strict;    #added to make our test suite happy.
}

# THE CODE BELOW WAS WRITTEN BY Damian Conway and is included here unchanged.

package Perl6::Say;
use IO::Handle;
$VERSION = '0.04';

# Implementation...
use Scalar::Util 'openhandle';
use Carp;

sub say
{
    my $handle = openhandle( $_[ 0 ] ) ? shift : \*STDOUT;
    @_ = $_ if !@_;
    my $warning;
    local $SIG{ __WARN__ } = sub { $warning = join q{}, @_ };
    my $res = print { $handle } @_, "\n";
    return $res if $res;

    # commenting this out b/c it makes say croak when the file handle is closed
    # $warning =~ s/[ ]at[ ].*//xms;
    # croak $warning;
}

# Handle direct calls...

sub import { *{ caller() . '::say' } = \&say; }

# Handle OO calls:

*IO::Handle::say = \&say;

1;
__END__

=head1 NAME

Perl6::Say - Implements the Perl 6 C<say> (C<print>-with-newline) function


=head1 SYNOPSIS

    # Perl 5 code...

    use Perl6::Say;

    say 'boo';             # same as:  print 'boo', "\n"

    say STDERR 'boo';      # same as:  print STDERR 'boo', "\n"

    STDERR->say('boo');    # same as:  print STDERR 'boo', \n"

    $fh->say('boo');       # same as:  print $fh 'boo', "\n";


=head1 DESCRIPTION

Implements a close simulation of C<say>, the Perl 6 print-with-newline
function.

Use it just like C<print> (except that it only supports the indirect object
syntax when the stream is a bareword). That is, assuming the relevant
filehandles are open for output, you can use any of these:

    say @data;
    say FH @data;
    say $fh, @data;
    FH->say(@data);
    *FH->say(@data);
    (\*FH)->say(@data);
    $fh->say(@data);

but not any of these:

    say {FH} @data;
    say {*FH} @data;
    say {\*FH} @data;
    say $fh @data;
    say {$fh} @data;


=head2 Interaction with output record separator

In Perl 6, S<C<say @stuff>> is exactly equivalent to
S<C<Core::print @stuff, "\n">>.

That means that a call to C<say> appends any output record separator
I<after> the added newline (though in Perl 6, the ORS is an attribute of
the filehandle being used, rather than a glonal C<$/> variable).


=head1 WARNING

The syntax and semantics of Perl 6 is still being finalized
and consequently is at any time subject to change. That means the
same caveat applies to this module.


=head1 DEPENDENCIES

None.

=head1 AUTHOR

Damian Conway (damian@conway.org)


=head1 BUGS AND IRRITATIONS

As far as I can determine, Perl 5 doesn't allow us to create a subroutine
that truly acts like C<print>. That is, one that can simultaneously be
used like so:

    say @data;

and like so:

    say {$fh} @data;

Comments, suggestions, and patches welcome.


=head1 COPYRIGHT

 Copyright (c) 2004, Damian Conway. All Rights Reserved.
 This module is free software. It may be used, redistributed
    and/or modified under the same terms as Perl itself.
