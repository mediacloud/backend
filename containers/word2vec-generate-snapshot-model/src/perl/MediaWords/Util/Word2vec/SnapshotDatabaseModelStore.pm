package MediaWords::Util::Word2vec::SnapshotDatabaseModelStore;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'mediawords.util.word2vec.model_stores' );

sub new($$$)
{
    my ( $class, $db, $snapshots_id ) = @_;

    my $self = {};
    bless $self, $class;

    $snapshots_id = int( $snapshots_id );

    $self->{ _python_object } =
      MediaWords::Util::Word2vec::SnapshotDatabaseModelStore::SnapshotDatabaseModelStore->new( $db, $snapshots_id );

    return $self;
}

1;
