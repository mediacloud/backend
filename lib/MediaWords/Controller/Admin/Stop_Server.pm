package MediaWords::Controller::Admin::Stop_Server;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

use strict;
use warnings;

#use parent 'Catalyst::Controller';
use parent 'Catalyst::Controller::HTML::FormFu';

sub quit : Global { exit( 0 ) }

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    if ( exists $ENV{ MEDIACLOUD_ENABLE_SHUTDOWN_URL } && $ENV{ MEDIACLOUD_ENABLE_SHUTDOWN_URL } )
    {
        say STDERR "quitting server";

        $c->response->body( "Shutting down server\n" );
        quit();
    }
    else
    {
        $c->response->body( '$MEDIACLOUD_ENABLE_SHUTDOWN_URL must be set to allow url based server shutdown' . "\n" );
    }

    return;
}

1;
