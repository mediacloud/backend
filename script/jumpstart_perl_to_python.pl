#!/usr/bin/env perl

# this script will jump start the process of converting perl scripts to python by translating simple repetitive
# perl to python tasks.  the resulting python code will almost certainly not run -- this is just intended to
# save typing for the simple obvious translations like function definitions and variable references.

use strict;
use warnings;

# convert 'MediaWords::Foo::Bar' to 'mediawords.foo.bar'
sub convert_perl_module_to_python_module($)
{
    my ( $s ) = @_;

    my $names = [ split( '::', $s ) ];

    return $s unless ( @{ $names } );

    return join( '.', map { lc( $_ ) } @{ $names } );
}

sub main
{
    my $lines = [ <> ];

    my $code = join( '', @{ $lines } );

    # remove perl boilerplate
    $code =~ s/^package .*\n//;
    $code =~ s/use (strict|warnings|Moose|Modern\:\:Perl.*|MediaWords\:\:CommonLibs)\;\n//g;
    $code =~ s/\nno Moose.*//;
    $code =~ s/\n__PACKAGE__.*//;

    # turn perldoc into heredoc (brittle for multiply =head# lines, but we can just manually fix
    $code =~ s/\n\=head\d.*\n/\n\"\"\"\n/g;
    $code =~ s/\n\=cut.*\n/\n\"\"\"\n/g;

    $code =~ s/\nuse /\nimport /g;

    # use -> import
    $code =~ s/(MediaWords.*)/convert_perl_module_to_python_module( $1 )/eg;

    # first try to convert function def with arguments, then just do the function def
    $code =~ s/sub (\w+)[^{]*\{\s+my \( ([^)]*) \) = \@(_|ARGV);/def $1($2):/sg;
    $code =~ s/sub (\w+)[^{]*\{/def $1():/sg;

    # try to move perl function comment into heredoc in python function
    $code =~ s/\n\#(.*)\ndef (.*)\n/\ndef $2\n    """$1"""\n\n/g;

    # convert perl if/while to python
    $code =~ s/(while|if) \( ([^\)]+) \)\n/$1 $2:\n/g;

    # convert perl for to python
    $code =~ s/for my \$(.+) \( (.+) \)/for $1 in $2:/g;

    # perl single line if
    $code =~ s/\n(\s*)(.*) if \( (.*) \)\;\n/\n$1if $3:\n$1    $2\n/g;

    # perl single line unless
    $code =~ s/\n(\s*)(.*) unless \( (.*) \)\;\n/\n$1if not $3:\n$1    $2\n/g;

    # conditional assignment
    $code =~ s/(\w+) = (.*) \? (.*) \: (.*)\;/$1 = \($3 if $2 else $4\)/g;

    # Readonly constants
    $code =~ s/Readonly my ([^ ]*)\s*\=\>\s*(.*)/$1 \= $2/g;

    # 'my $foo;' -> 'foo = None'
    $code =~ s/my \$(\w+)\;\n/$1 = None\n/g;

    # remove perl 'my'
    $code =~ s/my \$(\w+)/$1/g;

    # translate common use of scalar( @{ $foo } ) to len(foo)
    $code =~ s/scalar\( \@/len\( \@/g;

    # and && or
    $code =~ s/\&\&/and/g;
    $code =~ s/\|\|/or/g;

    # don't align assignments
    $code =~ s/(\s+)=/ =/g;

    # hash definitions
    $code =~ s/(\w+)(\s+)\=\>(.*)/'$1':$3/g;

    # remove variable decorators
    $code =~ s/\@\{ \$(\w+) \}/$1/g;
    $code =~ s/\%\{ \$(\w+) \}/$1/g;
    $code =~ s/[\$\@\%](\w+)/$1/g;

    # perl to python hash reference
    $code =~ s/\-\>\{ (\w+) \}/\[\'$1'\]/g;

    # perl to python method invocation
    $code =~ s/\-\>(\w+)/\.$1/g;

    # remove space padding in ()s and []s
    $code =~ s/\( ([^\)]+) \)/\($1\)/g;
    $code =~ s/\[ ([^\)]+) \]/\[$1\]/g;

    # rmeove semi-colons
    $code =~ s/\;//g;

    # ! -> not
    $code =~ s/\!/not /g;

    # remove brackets
    $code =~ s/\n[\s\{\}]+\n/\n\n/g;

    # python logging
    $code =~ s/DEBUG\(/log.debug\(/g;
    $code =~ s/TRACE\(/log.debug\(/g;
    $code =~ s/INFO\(/log.info\(/g;
    $code =~ s/WARN\(/log.warning\(/g;
    $code =~ s/ERROR\(/log.error\(/g;
    $code = "from mediawords.util.log import create_logger\nlog = create_logger(__name__)\n\n" . $code;

    # add ()s to common get_config use
    $code =~ s/\.get_config\[/\.get_config\(\)\[/g;

    # eq -> ==
    $code =~ s/ eq / == /g;

    print $code;
}

main();
