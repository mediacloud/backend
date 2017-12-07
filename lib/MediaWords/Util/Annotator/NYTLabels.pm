package MediaWords::Util::Annotator::NYTLabels;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

{

    package MediaWords::Util::Annotator::NYTLabels::Proxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;    # set PYTHONPATH too

    import_python_module( __PACKAGE__, 'mediawords.annotator.nyt_labels' );

    1;
}

sub new
{
    my ( $class ) = @_;

    my $self = {};
    bless $self, $class;

    $self->{ _annotator } = MediaWords::Util::Annotator::NYTLabels::Proxy::NYTLabelsAnnotator->new();

    return $self;
}

sub annotator_is_enabled($)
{
    my $self = shift;

    return $self->{ _annotator }->annotator_is_enabled();
}

sub story_is_annotatable($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    return $self->{ _annotator }->story_is_annotatable( $db, $stories_id );
}

sub story_is_annotated($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    return $self->{ _annotator }->story_is_annotated( $db, $stories_id );
}

sub annotate_and_store_for_story($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    return $self->{ _annotator }->annotate_and_store_for_story( $db, $stories_id );
}

sub fetch_annotation_for_story($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    return $self->{ _annotator }->fetch_annotation_for_story( $db, $stories_id );
}

sub update_tags_for_story($$$)
{
    my ( $self, $db, $stories_id ) = @_;

    return $self->{ _annotator }->update_tags_for_story( $db, $stories_id );
}

1;
