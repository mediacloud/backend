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

    # say STDERR "New database inline download storage.";
}

# Moose method
sub store_content($$$$)
{
    my ( $self, $db, $download, $content_ref ) = @_;

    my $path = 'content:' . $$content_ref;
    return $path;
}

# Moose method
sub fetch_content($$$)
{
    my ( $self, $db, $download ) = @_;

    my $content = $download->{ path };
    $content =~ s/^content://;
    return \$content;
}

# Moose method
sub remove_content($$$)
{
    my ( $self, $db, $download ) = @_;

    die "Not sure how to remove inline content for download " . $download->{ downloads_id } . "\n";

    return 0;
}

# Moose method
sub content_exists($$$)
{
    my ( $self, $db, $download ) = @_;

    die "Not sure how to check whether inline content exists for download " . $download->{ downloads_id } . "\n";

    return 0;
}

no Moose;    # gets rid of scaffolding

1;
