package MediaWords::Test::Types;

=head1 NAME

MediaWords::Test::Types - helper functions for types of variables

=cut

use strict;
use warnings;

use Test::Builder;
use base 'Test::Builder::Module';

use Data::Dumper;
use B 'svref_2object', 'SVf_IOK';

# Returns true if Perl thinks variable is an integer
sub _is_integer($)
{
    my $variable = shift;

    unless ( defined( $variable ) )
    {
        return 0;
    }

    my $flags = svref_2object( \$variable )->FLAGS;

    if ( $flags & SVf_IOK )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Succeeds if Perl thinks variable is an integer
sub is_integer($;$)
{
    my ( $variable, $name ) = @_;

    my $tb = __PACKAGE__->builder;

    if ( _is_integer( $variable ) )
    {
        $tb->ok( 1, $name );
    }
    else
    {
        $tb->ok( 0, $name );
        $tb->diag( "Variable is expected to be an integer: " . Dumper( $variable ) );
    }
}

# Succeeds if Perl doesn't think variable is an integer
sub isnt_integer($;$)
{
    my ( $variable, $name ) = @_;

    my $tb = __PACKAGE__->builder;

    unless ( _is_integer( $variable ) )
    {
        $tb->ok( 1, $name );
    }
    else
    {
        $tb->ok( 0, $name );
        $tb->diag( "Variable is not expected to be an integer: " . Dumper( $variable ) );
    }
}

1;
