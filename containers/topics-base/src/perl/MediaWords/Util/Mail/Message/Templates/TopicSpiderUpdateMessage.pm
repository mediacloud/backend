package MediaWords::Util::Mail::Message::Templates::TopicSpiderUpdateMessage;

use strict;
use warnings;

use parent 'MediaWords::Util::Mail::Message';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'topics_base.messages' );

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
    unless ( $args->{ topic_name } )
    {
        die "'topic_name' is unset.";
    }
    unless ( $args->{ topic_url } )
    {
        die "'topic_url' is unset.";
    }
    unless ( $args->{ topic_spider_status } )
    {
        die "'topic_spider_status' is unset.";
    }

    $self->{ python_message } =
      MediaWords::Util::Mail::Message::Templates::TopicSpiderUpdateMessage::TopicSpiderUpdateMessage->new(
        $args->{ to },
        $args->{ topic_name },
        $args->{ topic_url },
        $args->{ topic_spider_status },
      );

    return $self;
}

1;
