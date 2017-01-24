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
our @EXPORT = qw(make_python_variable_writable normalize_boolean_for_db);

use Carp;
use Inline::Python;
use Scalar::Util qw/looks_like_number/;

# Python function return values proxied through Inline::Python become read-only
# so attempts to modify them afterwards fail with:
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

        $copy = int( "$variable" ) ? 1 : 0;    # Cast to int

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

# Python's psycopg2 does not accept integers as valid boolean values, and
# there's no good way to cast them in the database handler itself. Thus, this
# subroutine normalizes various Perl boolean values to 't', 'f' and
# undef (NULL) which psycopg2 plays happily with.
sub normalize_boolean_for_db($;$)
{
    my ( $value, $allow_null ) = @_;

    if ( defined $value )
    {
        if ( ref( $value ) eq 'Inline::Python::Boolean' )
        {

            # Inline::Python boolean
            $value = int( $value );
            if ( $value )
            {
                return 't';
            }
            else
            {
                return 'f';
            }

        }
        else
        {
            if ( looks_like_number( $value ) )
            {

                # Integer
                $value = int( $value );
                if ( $value == 1 )
                {
                    return 't';
                }
                elsif ( $value == 0 )
                {
                    return 'f';
                }
                else
                {
                    croak "Invalid boolean value: $value";
                }

            }
            else
            {

                # String
                $value = lc( $value );

                if (   $value eq 't'
                    or $value eq 'true'
                    or $value eq 'y'
                    or $value eq 'yes'
                    or $value eq 'on'
                    or $value eq '1' )
                {
                    return 't';
                }
                elsif ($value eq 'f'
                    or $value eq 'false'
                    or $value eq 'n'
                    or $value eq 'no'
                    or $value eq 'off'
                    or $value eq '0' )
                {
                    return 'f';
                }
                else
                {
                    croak "Invalid boolean value: $value";
                }
            }
        }
    }
    else
    {
        if ( $allow_null )
        {
            # NULL is a valid "BOOLEAN" column value
            return undef;
        }
        else
        {
            return 'f';
        }
    }
}

1;
