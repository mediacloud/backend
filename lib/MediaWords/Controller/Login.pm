package MediaWords::Controller::Login;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

MediaWords::Controller::Login - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

Login

=cut

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    my $form_was_submitted = $c->request->params->{ submit };

    if ( $form_was_submitted )
    {
        my $email    = $c->request->params->{ email };
        my $password = $c->request->params->{ password };

        if ( $email && $password )
        {

            # Attempt to log the user in
            if ( $c->authenticate( { username => $email, password => $password } ) )
            {

                # If successful, redirect to default homepage
                my $config            = MediaWords::Util::Config::get_config;
                my $default_home_page = $config->{ mediawords }->{ default_home_page };
                $c->response->redirect( $c->uri_for( $default_home_page ) );

                return;
            }
            else
            {

                # Set an error message
                $c->stash( error_msg => "Bad email and / or password." );
            }
        }
        else
        {

            # Set an error message
            $c->stash( error_msg => "Empty email and / or password." )
              unless ( $c->user_exists );
        }
    }

    $c->stash->{ c } = $c;
    $c->stash( template => 'auth/login.tt2' );
}

=head1 AUTHOR

Linas Valiukas

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
