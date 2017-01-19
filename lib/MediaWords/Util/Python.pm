package MediaWords::Util::Python;

#
# Utilities assisting in Perl - Python binding code
#

use strict;
use warnings;

use Modern::Perl "2015";

our @ISA    = qw(Exporter);
our @EXPORT = qw(make_python_variable_writable);

use Carp;
use Clone qw(clone);

# Python function return values proxied through Inline::Python become read-only so attempts to modify them afterwards fail with:
#
#     Modification of non-creatable hash value attempted, subscript "language"
#
# To make the return values writable, we simply clone them.
sub make_python_variable_writable($)
{
    my $variable = shift;

    my $cloned_variable;
    eval { $cloned_variable = clone( $variable ); };
    if ( $@ )
    {
        # Print stack trace which led to this mishap
        confess "Cloning variable failed: $@; variable: $variable";
    }

    return $cloned_variable;
}

1;
