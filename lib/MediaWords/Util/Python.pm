package MediaWords::Util::Python;

#
# Utilities assisting in Perl - Python binding code
#
# MC_REWRITE_TO_PYTHON: remove after porting (naturally)
#

use strict;
use warnings;

use Modern::Perl "2015";

our @ISA    = qw(Exporter);
our @EXPORT = qw(make_python_variable_writable);

use Carp;
use Inline::Python;

# Python function return values proxied through Inline::Python become read-only so attempts to modify them afterwards fail with:
#
#     Modification of non-creatable hash value attempted, subscript "language"
#
# To make the return values writable, we simply clone them.
sub make_python_variable_writable
{
    my $variable = shift;

    my $copy;

    # Neither clone() from Clone nor dclone() from Storable flattens
    # Inline::Python's booleans as we want, so here goes our own deep copy
    if ( ref( $variable ) eq ref( [] ) )
    {
        # Arrayref
        $copy = [];
        foreach my $value ( @{ $variable } )
        {
            my $writable_value = make_python_variable_writable( $value );
            push( @{ $copy }, $writable_value );
        }

    }
    elsif ( ref( $variable ) eq ref( {} ) )
    {
        # Hashref
        $copy = {};
        foreach my $key ( keys %{ $variable } )
        {
            my $value = $variable->{ $key };

            my $writable_key   = make_python_variable_writable( $key );
            my $writable_value = make_python_variable_writable( $value );
            $copy->{ $writable_key } = $writable_value;
        }

    }
    elsif ( ref( $variable ) eq 'Inline::Python::Boolean' )
    {
        # Inline::Python booleans

        $copy = int( "$variable" );
        if ( $copy )
        {
            $copy = $Inline::Python::Boolean::true;
        }
        else
        {
            $copy = $Inline::Python::Boolean::false;
        }

    }
    elsif ( ref( $variable ) )
    {
        # Some other object
        $copy = scalar( $variable );

    }
    else
    {
        $copy = $variable;

    }

    return $copy;
}

1;
