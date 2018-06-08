package MediaWords::Util::Word2vec;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Word2vec::SnapshotDatabaseModelStore;

{

    package MediaWords::Util::Word2vec::Proxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    import_python_module( __PACKAGE__, 'mediawords.util.word2vec' );
}

sub load_word2vec_model($$)
{
    my ( $model_store, $models_id ) = @_;

    $models_id = int( $models_id );

    return MediaWords::Util::Word2vec::Proxy::load_word2vec_model( $model_store->{ _python_object }, $models_id );
}

1;
