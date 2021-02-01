package MediaWords::Util::Python;

#
# Utilities assisting in Perl - Python binding code
#
# MC_REWRITE_TO_PYTHON: remove after porting (naturally)
#

use strict;
use warnings;

use Modern::Perl "2015";

# Deliberately don't include MediaWords::CommonLibs as it includes this package itself

our @ISA    = qw(Exporter);
our @EXPORT = qw(import_python_module python_deep_copy normalize_boolean_for_db);

use Carp;
use Data::Dumper;
use Inline::Python qw(py_eval py_bind_class py_bind_func py_study_package);
use Scalar::Util qw/looks_like_number/;

# Some Python libraries depend on sys.executable being set which doesn't get set when used via Inline::Python, e.g. Celery fails with:
#
# [2021-01-25 10:58:47,473: CRITICAL/MainProcess] Unrecoverable error: IsADirectoryError(21, 'Is a directory')
# Traceback (most recent call last):
#   File "/usr/local/lib/python3.8/dist-packages/celery/worker/worker.py", line 203, in start
#     self.blueprint.start(self)
#   File "/usr/local/lib/python3.8/dist-packages/celery/bootsteps.py", line 112, in start
#     self.on_start()
#   File "/usr/local/lib/python3.8/dist-packages/celery/apps/worker.py", line 136, in on_start
#     self.emit_banner()
#   File "/usr/local/lib/python3.8/dist-packages/celery/apps/worker.py", line 170, in emit_banner
#     ' \n', self.startup_info(artlines=not use_image))),
#   File "/usr/local/lib/python3.8/dist-packages/celery/apps/worker.py", line 234, in startup_info
#     platform=safe_str(_platform.platform()),
#   File "/usr/lib/python3.8/platform.py", line 1206, in platform
#     libcname, libcversion = libc_ver(sys.executable)
#   File "/usr/lib/python3.8/platform.py", line 193, in libc_ver
#     with open(executable, 'rb') as f:
# IsADirectoryError: [Errno 21] Is a directory: '/'
#
py_eval( <<EOF

import sys

if not sys.executable:
    sys.executable = '/usr/bin/python3'

EOF
);

# Import all functions and classes from Python module to Perl package (not into
# the main namespace as is the default by Inline::Python).
#
# Usage:
#
# import_python_module(__PACKAGE__, 'mediawords.util.foo');
#
sub import_python_module($$)
{
    my ( $perl_package_name, $python_module_name ) = @_;

    # say STDERR "Importing Python module '$python_module_name'...";
    py_eval( "import $python_module_name" );

    # say STDERR "Fetching namespace of Python module '$python_module_name'...";
    my %namespace = py_study_package( $python_module_name );

    local $SIG{ __WARN__ } = sub {
        my $warning = shift;

        # For whatever reason, Inline::Python warns on an attempt to import
        # exception and type classes (e.g. "Optional") with:
        #
        # Illegal character in prototype for <...>Exception::ARRAY : 0x7fd3d2890808 at (eval 379) line 12.
        #

        if ( $warning =~ /^Illegal character in prototype for .+?::ARRAY/ )
        {
            # no-op
        }
        else
        {
            warn $warning;
        }
    };

    # say STDERR "Importing classes from Python module '$python_module_name' to Perl package '$perl_package_name'...";
    for my $class_name ( keys %{ $namespace{ 'classes' } } )
    {
        my $target_class_name = $perl_package_name . '::' . $class_name;

        # say STDERR "Importing Python class '$target_class_name' from module '$python_module_name'";
        my @class_methods = $namespace{ 'classes' }{ $class_name };
        py_bind_class( $target_class_name, $python_module_name, $class_name, @class_methods );
    }

    # say STDERR "Importing functions from Python module '$python_module_name' to Perl package '$perl_package_name'...";
    for my $function_name ( @{ $namespace{ 'functions' } } )
    {
        my $target_function_name = $perl_package_name . '::' . $function_name;

        # say STDERR "Importing Python function '$target_function_name' from module '$python_module_name'";
        py_bind_func( $target_function_name, $python_module_name, $function_name );
    }

    local $SIG{ __WARN__ } = undef;

    # say STDERR "Done importing Python module '$python_module_name'.";
}

# Python function return values proxied through Inline::Python become read-only
# so attempts to modify them afterwards fail with:
#
#     Modification of non-creatable hash value attempted, subscript "language"
#
# To make the return values writable, we simply clone them.
#
# If $cast_bools_to_int is set, cast Inline::Python booleans to ints instead of
# leaving them as-is.
sub python_deep_copy($;$);

sub python_deep_copy($;$)
{
    my ( $variable, $cast_bools_to_int ) = @_;

    my $copy;

    # Neither clone() from Clone nor dclone() from Storable flattens
    # Inline::Python's booleans as we want, so here goes our own deep copy
    if ( ref( $variable ) eq ref( [] ) )
    {
        # Arrayref
        $copy = [];
        foreach my $value ( @{ $variable } )
        {
            my $writable_value = python_deep_copy( $value, $cast_bools_to_int );
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

            my $writable_key   = python_deep_copy( $key,   $cast_bools_to_int );
            my $writable_value = python_deep_copy( $value, $cast_bools_to_int );
            $copy->{ $writable_key } = $writable_value;
        }

    }
    elsif ( ref( $variable ) eq 'Inline::Python::Boolean' )
    {
        # Inline::Python booleans

        $copy = int( "$variable" );
        if ( $copy )
        {
            $copy = $cast_bools_to_int ? 1 : $Inline::Python::Boolean::true;
        }
        else
        {
            $copy = $cast_bools_to_int ? 0 : $Inline::Python::Boolean::false;
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
                    confess "Invalid boolean value: " . Dumper( $value );
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
                elsif (
                       $value eq 'f'
                    or $value eq 'false'
                    or $value eq 'n'
                    or $value eq 'no'
                    or $value eq 'off'
                    or $value eq '0'
                    or $value eq ''    # coming from Catalyst form
                  )
                {
                    return 'f';
                }
                else
                {
                    confess "Invalid boolean value: " . Dumper( $value );
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

# return true if the caller is 'Inline::Python', which indicates the function was called from python
sub called_from_python()
{
    return ( ( caller( 1 ) )[ 0 ] eq 'Inline::Python' );
}

1;
