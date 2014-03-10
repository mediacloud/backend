package MediaWords::KeyValueStore::DatabaseInline;

# class for storing / loading very short downloads directly in the
# "downloads.path" column

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2013";
use MediaWords::CommonLibs;

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    # say STDERR "New database inline storage.";
}

# Moose method
sub store_content($$$$;$)
{
    my ( $self, $db, $object_id, $content_ref, $skip_encode_and_gzip ) = @_;

    my $path = 'content:' . $$content_ref;
    return $path;
}

# Moose method
sub fetch_content($$$$;$)
{
    my ( $self, $db, $object_id, $object_path, $skip_gunzip_and_decode ) = @_;

    unless ( defined $object_path )
    {
        die "Object path for object ID $object_id is undefined.\n";
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
        die "Object path for object ID $object_id is undefined.\n";
    }

    die "Not sure how to remove inline content for object ID $object_id.\n";

    return 0;
}

# Moose method
sub content_exists($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    unless ( defined $object_path )
    {
        die "Object path for object ID $object_id is undefined.\n";
    }

    die "Not sure how to check whether inline content exists for object ID $object_id.\n";

    return 0;
}

no Moose;    # gets rid of scaffolding

1;
