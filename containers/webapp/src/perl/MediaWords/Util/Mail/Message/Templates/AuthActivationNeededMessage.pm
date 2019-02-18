package MediaWords::Util::Mail::Message::Templates::AuthActivationNeededMessage;

use strict;
use warnings;

use parent 'MediaWords::Util::Mail::Message';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.util.mail_message.templates.webapp_messages' );

sub new
{
    my ( $class, $args ) = @_;

    my $self = {};
    bless $self, $class;

    # Inline::Python will throw very unfriendly errors on missing arguments, so double-check here
    unless ( $args->{ to } )
    {
        die "'to' is unset.";
    }
    unless ( $args->{ full_name } )
    {
        die "'full_name' is unset.";
    }
    unless ( $args->{ activation_url } )
    {
        die "'activation_url' is unset.";
    }
    unless ( defined $args->{ subscribe_to_newsletter } )
    {
        die "'subscribe_to_newsletter' is undefined.";
    }

    $self->{ python_message } =
      MediaWords::Util::Mail::Message::Templates::AuthActivationNeededMessage::AuthActivationNeededMessage->new(
        $args->{ to },
        $args->{ full_name },
        $args->{ activation_url },
        $args->{ subscribe_to_newsletter }
      );

    return $self;
}

1;
