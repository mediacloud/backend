package MediaWords::Util::Annotator::AnnotatorTag;

#
# Single tag derived from JSON annotation
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Moose;

has 'tag_sets_name'        => ( is => 'rw', isa => 'Str', required => 1 );
has 'tag_sets_label'       => ( is => 'rw', isa => 'Str', required => 1 );
has 'tag_sets_description' => ( is => 'rw', isa => 'Str', required => 1 );

has 'tags_name'        => ( is => 'rw', isa => 'Str', required => 1 );
has 'tags_label'       => ( is => 'rw', isa => 'Str', required => 1 );
has 'tags_description' => ( is => 'rw', isa => 'Str', required => 1 );

no Moose;    # gets rid of scaffolding

1;
