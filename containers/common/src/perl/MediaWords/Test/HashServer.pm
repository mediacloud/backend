package MediaWords::Test::HashServer;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.test.hash_server' );

sub new
{
    my ( $class, $port, $pages ) = @_;

    my $self = {};
    bless $self, $class;

    # Make deep copies because (probably) HashServer implementation modifies
    # the hashref in some way, making it unusable in Perl code afterwards
    # (e.g. in Cache.t)
    $port  = python_deep_copy( $port );
    $pages = python_deep_copy( $pages );

    # Create Python object (first ::HashServer is Perl package, second ::HashServer is Python class)
    $self->{ python_hashserver } = MediaWords::Test::HashServer::HashServer->new( $port, $pages );

    return $self;
}

sub start
{
    my $self = shift;
    $self->{ python_hashserver }->start();
}

sub stop
{
    my $self = shift;
    $self->{ python_hashserver }->stop();
}

sub page_url
{
    my ( $self, $path ) = @_;
    my $return_value = $self->{ python_hashserver }->page_url( $path );
    return python_deep_copy( $return_value );
}

1;
