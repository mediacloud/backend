#
# $Id: Optimizer.pm,v 0.15 2004/12/05 16:07:34 dankogai Exp dankogai $
#

##
## We are mirroring the regexp::optimizer module here because it is difficult to install from CPAN
#
# The module can be obtained from:
## http://search.cpan.org/~dankogai/Regexp-Optimizer-0.15/lib/Regexp/Optimizer.pm
##
##


package Regexp::Optimizer;
use 5.006; # qr/(??{}/ needed
use strict;
use warnings;
use base qw/Regexp::List/;
our $VERSION = do { my @r = (q$Revision: 0.15 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };

#our @EXPORT = qw();
#our %EXPORT_TAGS = ( 'all' => [ qw() ] );
#our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );
#our $DEBUG     = 0;

# see perldoc perlop

# perldoc perlop on perl 5.8.4 or later
#
#  Pragmata are now correctly propagated into (?{...}) constructions in
#  regexps.  Code such as
#
#    my $x = qr{ ... (??{ $x }) ... };
#
#   will now (correctly) fail under use strict. (As the inner $x is 
#   and has always referred to $::x)

our $RE_PAREN; # predeclear
$RE_PAREN = 
    qr{
       \(
       (?:
	(?> [^()]+ )
	|
	(??{ $RE_PAREN })
       )*
       \)
      }xo;
our $RE_EXPR; # predeclear
$RE_EXPR = 
    qr{
       \{
       (?:
	(?> [^{}]+ )
	|
	(??{ $RE_EXPR })
       )*
       \}
      }xo;
our $RE_PIPE = qr/(?!\\)\|/o;
our $RE_CHAR = 
    qr{(?:
	# single character...
	(?!\\)[^\\\[(|)\]]       | # raw character except '[(|)]'
	$Regexp::List::RE_XCHAR  | # extended characters
       )}xo;
our $RE_CCLASS = 
    qr{(?:
	(?!\\)\[ $RE_CHAR+? \] |
	$Regexp::List::RE_XCHAR      | # extended characters
	(?!\\)[^(|)]                 | # raw character except '[(|)]'
	# Note pseudo-characters are not included
    )}xo;
our $RE_QUANT =
    qr{(?:
	(?!\\)
	    (?:
	     \? |
	     \+ |
	     \* |
	     \{[\d,]+\}
	     )\??
	)}xo;
our $RE_TOKEN = 
    qr{(?:
	(?:
	\\[ULQ] (?:$RE_CHAR+)(?:\\E|$) | # [ul]c or quotemeta
        $Regexp::List::RE_PCHAR  | # pseudo-characters
        $RE_CCLASS |
	$RE_CHAR     
       )
	 $RE_QUANT?
       )}xo;
our $RE_START = $Regexp::List::RE_START;

our %PARAM = (meta      => 1,
	      quotemeta => 0,
	      lookahead => 0,
	      optim_cc  => 1,
	      modifiers => '',
	      _char     => $RE_CHAR,
	      _token    => $RE_TOKEN,
	      _cclass   => $RE_CCLASS,
	     );

sub new{
    my $class = ref $_[0] ? ref shift : shift;
    my $self = $class->SUPER::new;
    $self->set(%PARAM, @_);
    $self;
}

sub list2re{
    shift->SUPER::list2re(map {_strip($_)} @_);
}

sub optimize{
    my $self = shift;
    my $str  = shift;
    $self->{unexpand} and $str = $self->unexpand($str);
    # safetey feature against qq/(?:foo)(?:bar)/
    !ref $str and $str =~ /^$RE_START/ and $str = qr/$str/;
    my $re = $self->_optimize($str);
    qr/$re/;
}

sub _strip{
    my ($str, $force) = @_;
    $force or ref $str eq 'Regexp' or return $str;
    $str =~ s/^($RE_START)//o or return $str;
    my $regopt = $1;  $str =~ s/\)$//o;
    $regopt =~ s/^\(\??//o; 
    $regopt =~ /^[-:]/ and $regopt = undef;
    ($str, $regopt);
}

my %my_l2r_opts = 
    (
     as_string => 1, 
     debug     => 0,
     _token    => qr/$RE_PAREN$RE_QUANT?|$RE_PIPE|$RE_TOKEN/,
    );

sub _optimize{
    no warnings 'uninitialized';
    my $self = shift;
    $self->{debug} and $self->{_indent}++;
    $self->{debug} and
	print STDERR '>'x $self->{_indent}, " ", $_[0], "\n";
    my ($result, $regopt)  = _strip(shift, 1);
    $result =~ s/\\([()])/"\\x" . sprintf("%X", ord($1))/ego;
    # $result =~ s/(\s)/"\\x" . sprintf("%X", ord($1))/ego;
    $result !~ /$RE_PIPE/ and goto RESULT;
    my $l = $self->clone->set(%my_l2r_opts);
    # optimize
    unless ($result =~ /$RE_PAREN/){
        my @words = split /$RE_PIPE/ => $result;
        $result = $l->list2re(@words);
	goto RESULT;
    }
    my (@term, $sp);
    while ($result){
	if ($result =~ s/^($RE_PAREN)($RE_QUANT?)//){
	    my ($term, $quant) = ($1, $2);
	    $term = $self->_optimize($term);
	    $l->{optim_cc} = $quant ? 0 : 1;
	    if ($quant){
		if ($term =~ /^$self->{_cclass}$/){
		    $term .= $quant;
		}else{
		    $term = $self->{po} . $term . $self->{pc} . $quant;
		}
	    }
	    $term[$sp] .= $term;
	}elsif($result =~ s/^$RE_PIPE//){
	    $sp += 2;
	    push @term, '|';
	}elsif($result =~ s/^($RE_TOKEN+)//){
	    # warn $1;
	    $term[$sp] .= $1;
	}else{
	    die "something is wrong !";
	}
    }
    # warn scalar @term , ";", join(";" => @term);
    # sleep 1;
    my @stack;
    while (my $term = shift @term){
	if ($term eq '|'){
	    push @stack, $l->list2re(pop @stack, shift @term);
	}else{
	    push @stack, $term;
	}
    }
    $result = join('' => @stack);
 RESULT:
    $result =  $regopt ? qq/(?$regopt$result)/ : $result;
    # warn qq($result, $regopt);
    $self->{debug} and 
	print STDERR '<'x $self->{_indent}, " ", $result, "\n";
    $self->{debug} and $self->{_indent}--;
    $result;
}

sub _pair2re{
    my $self = shift;
    $_[0] eq $_[1] and return $_[0];
    my ($first, $second) =
	length $_[0] <= length $_[1] ? @_ : ($_[1], $_[0]);
    my $l = length($first);
    $l -= 1
	while $self->_head($first, $l) ne $self->_head($second, $l);
    $l > 0 or return join("", @_);
    return $self->_head($first, $l) . 
	$self->{po} . 
	$self->_tail($first, $l) . '|' . $self->_tail($second, $l) .
	$self->{pc};
}

1;
__END__

# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Regexp::Optimizer - optimizes regular expressions

=head1 SYNOPSIS

  use Regexp::Optimizer;
  my $o  = Regexp::Optimizer->new;
  my $re = $o->optimize(qr/foobar|fooxar|foozap/);
  # $re is now qr/foo(?:[bx]ar|zap)/

=head1 ABSTRACT

This module does, ahem, attempts to, optimize regular expressions.

=head1 INSTALLATION

To install this module type the following:

   perl Makefile.PL
   make
   make test
   make install

=head1 DESCRIPTION

Here is a quote from L<perltodo>.

=over

Factoring out common suffices/prefices in regexps (trie optimization)

Currently, the user has to optimize "foo|far" and "foo|goo" into
"f(?:oo|ar)" and "[fg]oo" by hand; this could be done automatically.

=back

This module implements just that.

=head2 EXPORT

Since this is an OO module there is no symbol exported.

=head1 METHODS

This module is implemented as a subclass of L<Regexp::List>.  For
methods not listed here, see L<Regexp::List>.

=over

=item $o  = Regexp::Optimizer->new;

=item $o->set(I<< key => value, ... >>)

Just the same us L<Regexp::List> except for the attribute below;

=over

=item unexpand

When set to one, $o->optimize() tries to $o->expand before actually
starting the operation.

  # cases you need to set expand => 1
  $o->set(expand => 1)->optimize(qr/
                                   foobar|
                                   fooxar|
                                   foozar
                                   /x);

=back

=item $re = $o->optimize(I<regexp>);

Does the job.  Note that unlike C<< ->list2re() >> in L<Regexp::List>,
the argument is the regular expression itself.  What it basically does
is to find groups will alterations and replace it with the result of
C<< $o->list2re >>.

=item $re = $o->list2re(I<list of words ...>)

Same as C<list2re()> in L<Regexp::List> in terms of functionality but
how it tokenize "atoms" is different since the arguments can be
regular expressions, not just strings.  Here is a brief example.

  my @expr = qw/foobar fooba+/;
  Regexp::List->new->list2re(@expr) eq qr/fooba[\+r]/;
  Regexp::Optimizer->new->list2re(@expr) eq qr/foob(?:a+ar)/;

=back

=head1 CAVEATS

This module is still experimental.  Do not assume that the result is
the same as the unoptimized version.

=over

=item *

When you just want a regular expression which matches normal words
with not metacharacters, use <Regexp::List>.  It's more robus and 
much faster.

=item *

When you have a list of regular expessions which you want to
aggregate, use C<list2re> of THIS MODULE.

=item *

Use C<< ->optimize() >> when and only when you already have a big
regular expression with alterations therein.

C<< ->optimize() >> does support nested groups but its parser is not
tested very well.

=back

=head1 BUGS

=over

=item *

Regex parser in this module (which itself is implemented by regular
expression) is not as thoroughly tested as L<Regexp::List>

=item *

May still fall into deep recursion when you attempt to optimize
deeply nested regexp.  See L</PRACTICALITY>.

=item *

Does not grok (?{expression}) and (?(cond)yes|no) constructs yet

=item *

You need to escape characters in character classes.

  $o->optimize(qr/[a-z()]|[A-Z]/);              # wrong
  $o->optimize(qr/[a-z\(\)]|[A-Z]/);            # right
  $o->optimize(qr/[0-9A-Za-z]|[\Q-_.!~*"'()\E]/ # right, too. 

=item *

When character(?: class(?:es)?)? are aggregated, duplicate ranges are
left as is.  Though functionally OK, it is cosmetically ugly.

  $o->optimize(qr/[0-5]|[5-9]|0123456789/);
  # simply turns into [0-5][5-9]0123456789] not [0-9]

I left it that way because marking-rearranging approach can result a
humongous result when unicode characters are concerned (and
\p{Properties}).

=back

=head1 PRACTICALITY

Though this module is still experimental, It is still good enough even
for such deeply nested regexes as the followng.

  # See 3.2.2 of  http://www.ietf.org/rfc/rfc2616.txt
  # BNF faithfully turned into a regex
  http://(?:(?:(?:(?:(?:[a-z]|[A-Z])|[0-9])|(?:(?:[a-z]|[A-Z])|[0-9])(?:(?:(?:[a-z]|[A-Z])|[0-9])|-)*(?:(?:[a-z]|[A-Z])|[0-9]))\.)*(?:(?:[a-z]|[A-Z])|(?:[a-z]|[A-Z])(?:(?:(?:[a-z]|[A-Z])|[0-9])|-)*(?:(?:[a-z]|[A-Z])|[0-9]))\.?|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(?::[0-9]*)?(?:/(?:(?:(?:(?:[a-z]|[A-Z])|[0-9])|[\-\_\.\!\~\*\'\(\)])|%(?:[0-9]|[A-Fa-f])(?:[0-9]|[A-Fa-f])|[:@&=+$,])*(?:;(?:(?:(?:(?:[a-z]|[A-Z])|[0-9])|[\-\_\.\!\~\*\'\(\)])|%(?:[0-9]|[A-Fa-f])(?:[0-9]|[A-Fa-f])|[:@&=+$,])*)*(?:/(?:(?:(?:(?:[a-z]|[A-Z])|[0-9])|[\-\_\.\!\~\*\'\(\)])|%(?:[0-9]|[A-Fa-f])(?:[0-9]|[A-Fa-f])|[:@&=+$,])*(?:;(?:(?:(?:(?:[a-z]|[A-Z])|[0-9])|[\-\_\.\!\~\*\'\(\)])|%(?:[0-9]|[A-Fa-f])(?:[0-9]|[A-Fa-f])|[:@&=+$,])*)*)*(?:\\?(?:[;/?:@&=+$,]|(?:(?:(?:[a-z]|[A-Z])|[0-9])|[\-\_\.\!\~\*\'\(\)])|%(?:[0-9]|[A-Fa-f])(?:[0-9]|[A-Fa-f]))*)?)?

  # and optimized
  http://(?::?[a-zA-Z0-9](?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?\.[a-zA-Z]*(?:[a-zA-Z0-9\-]*[a-zA-Z0-9])?\.?|[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(?::[0-9]*)?(?:/(?:(?:(?:[a-zA-Z0-9\-\_\.\!\~\*\'\x28\x29]|%[0-9A-Fa-f][0-9A-Fa-f])|[:@&=+$,]))*(?:;(?:(?:(?:[a-zA-Z0-9\-\_\.\!\~\*\'\x28\x29]|%[0-9A-Fa-f][0-9A-Fa-f])|[:@&=+$,]))*)*(?:/(?:(?:(?:[a-zA-Z0-9\-\_\.\!\~\*\'\x28\x29]|%[0-9A-Fa-f][0-9A-Fa-f])|[:@&=+$,]))*(?:;(?:(?:(?:[a-zA-Z0-9\-\_\.\!\~\*\'\x28\x29]|%[0-9A-Fa-f][0-9A-Fa-f])|[:@&=+$,]))*)*)*(?:\\?(?:(?:[;/?:@&=+$,a-zA-Z0-9\-\_\.\!\~\*\'\x28\x29]|%[0-9A-Fa-f][0-9A-Fa-f]))*)?)?

By carefully examine both you can find that character classes are
properly aggregated.

=head1 SEE ALSO

L<Regexp::List> -- upon which this module is based

C<eg/> directory in this package contains example scripts.

=over

=item Perl standard documents

 L<perltodo>, L<perlre>

=item CPAN Modules

L<Regexp::Presuf>, L<Text::Trie>

=item Books

Mastering Regular Expressions  L<http://www.oreilly.com/catalog/regex2/>

=back

=head1 AUTHOR

Dan Kogai <dankogai@dan.co.jp>

=head1 COPYRIGHT AND LICENSE

Copyright 2003 by Dan Kogai

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
