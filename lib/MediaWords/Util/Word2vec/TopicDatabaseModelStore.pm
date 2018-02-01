package MediaWords::Util::Word2vec::TopicDatabaseModelStore;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.util.word2vec.model_stores' );

sub new($$$)
{
    my ( $class, $db, $topics_id ) = @_;

    my $self = {};
    bless $self, $class;

    $topics_id = int( $topics_id );

    $self->{ _python_object } =
      MediaWords::Util::Word2vec::TopicDatabaseModelStore::TopicDatabaseModelStore->new( $db, $topics_id );

    return $self;
}

1;
