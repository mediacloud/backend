package MediaWords::DBI::Downloads::Store::DatabaseInline;

# class for storing / loading downloads in remote locations via HTTP

use strict;
use warnings;

use Moose;
with 'MediaWords::DBI::Downloads::Store';

use Modern::Perl "2013";
use MediaWords::CommonLibs;

# Constructor
sub BUILD
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
sub fetch_content($$)
{
    my ( $self, $download ) = @_;

    my $content = $download->{ path };
    $content =~ s/content://;
    return \$content;
}

no Moose;    # gets rid of scaffolding

1;
