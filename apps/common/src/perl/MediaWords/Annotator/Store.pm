package MediaWords::Annotator::Store;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

{

    package MediaWords::Annotator::Store::Proxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;    # set PYTHONPATH too

    import_python_module( __PACKAGE__, 'mediawords.annotator.store' );

    1;
}

sub new
{
    my ( $class, $raw_annotations_table ) = @_;

    my $self = {};
    bless $self, $class;

    $self->{ _store } = MediaWords::Annotator::Store::Proxy::JSONAnnotationStore->new( $raw_annotations_table );

    return $self;
}

sub story_is_annotated($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    return $self->{ _annotator }->story_is_annotated( $db, $stories_id );
}

sub fetch_annotation_for_story($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    return $self->{ _store }->fetch_annotation_for_story( $db, $stories_id );
}

1;
