package MediaWords::Test::HTTP::HashServer;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;    # set PYTHONPATH too

import_python_module( __PACKAGE__, 'mediawords.test.http.hash_server' );

sub new
{
    my ( $class, $port, $pages ) = @_;

    my $self = {};
    bless $self, $class;

    # Create Python object (::HashServer::HashServer)
    $self->{ python_hashserver } = MediaWords::Test::HTTP::HashServer::HashServer->new( $port, $pages );

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
