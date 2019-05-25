package MediaWords::Util::Mail::Message;

#
# Proxy package between Python's Message class (util/mail/message.py) and Perl code

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.util.mail' );

sub new
{
    my ( $class, $args ) = @_;

    my $self = {};
    bless $self, $class;

    # Create Python object (::Message::Message)
    $self->{ python_message } = MediaWords::Util::Mail::Message::Message->new(
        $args->{ to },
        $args->{ subject },
        $args->{ text_body },
        $args->{ html_body },
        $args->{ cc },
        $args->{ bcc },
    );

    return $self;
}

sub from($)
{
    my $self         = shift;
    my $return_value = $self->{ python_message }->{ from_ };    # note the underscore
    return python_deep_copy( $return_value );
}

sub to($)
{
    my $self         = shift;
    my $return_value = $self->{ python_message }->{ to };
    return python_deep_copy( $return_value );
}

sub cc($)
{
    my $self         = shift;
    my $return_value = $self->{ python_message }->{ cc };
    return python_deep_copy( $return_value );
}

sub bcc($)
{
    my $self         = shift;
    my $return_value = $self->{ python_message }->{ bcc };
    return python_deep_copy( $return_value );
}

sub subject($)
{
    my $self         = shift;
    my $return_value = $self->{ python_message }->{ subject };
    return python_deep_copy( $return_value );
}

sub text_body($)
{
    my $self         = shift;
    my $return_value = $self->{ python_message }->{ text_body };
    return python_deep_copy( $return_value );
}

sub html_body($)
{
    my $self         = shift;
    my $return_value = $self->{ python_message }->{ html_body };
    return python_deep_copy( $return_value );
}

1;
