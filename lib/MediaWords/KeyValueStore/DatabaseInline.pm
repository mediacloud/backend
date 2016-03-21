package MediaWords::KeyValueStore::DatabaseInline;

# class for storing / loading very short downloads directly in the
# "downloads.path" column

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use Carp;

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    # say STDERR "New database inline storage.";
}

# Moose method
sub store_content($$$$)
{
    my ( $self, $db, $object_id, $content_ref ) = @_;

    my $path = 'content:' . $$content_ref;
    return $path;
}

# Moose method
sub fetch_content($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    unless ( defined $object_path )
    {
        confess "Object path for object ID $object_id is undefined.";
    }

    my $content = $object_path;
    $content =~ s/^content://;
    return \$content;
}

# Moose method
sub remove_content($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    unless ( defined $object_path )
    {
        confess "Object path for object ID $object_id is undefined.";
    }

    confess "Not sure how to remove inline content for object ID $object_id.";

    return 0;
}

# Moose method
sub content_exists($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    unless ( defined $object_path )
    {
        say STDERR "Object path for object ID $object_id is undefined.";
        return 0;
    }

    if ( $object_path =~ /^content:/ )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

no Moose;    # gets rid of scaffolding

1;
