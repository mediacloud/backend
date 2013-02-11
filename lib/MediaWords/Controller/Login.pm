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

# Login form
sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/auth/login.yml',
            method           => 'POST',
            action           => $c->uri_for( '/login' ),
        }
    );

    $form->process( $c->request );

    if ( !$form->submitted_and_valid() )
    {
        $c->stash->{ form } = $form;
        $c->stash->{ c }    = $c;
        $c->stash( template => 'auth/login.tt2' );
        return;
    }

    my $email    = $form->param_value( 'email' );
    my $password = $form->param_value( 'password' );

    if ( !( $email && $password ) )
    {
        unless ( $c->user_exists )
        {
            $c->stash->{ form } = $form;
            $c->stash->{ c }    = $c;
            $c->stash( template  => 'auth/login.tt2' );
            $c->stash( error_msg => "Empty email address and / or password." );
            return;
        }
    }

    # Attempt to log the user in
    if ( !$c->authenticate( { username => $email, password => $password } ) )
    {
        $c->stash->{ form } = $form;
        $c->stash->{ c }    = $c;
        $c->stash( template  => 'auth/login.tt2' );
        $c->stash( error_msg => "Incorrect email address and / or password." );
        return;
    }

    # Reset the password reset token (if any)
    $c->dbis->query(
        <<"EOF",
        UPDATE auth_users
        SET password_reset_token = NULL
        WHERE email = ?
EOF
        $email
    );

    # If successful, redirect to default homepage
    my $config            = MediaWords::Util::Config::get_config;
    my $default_home_page = $config->{ mediawords }->{ default_home_page };
    $c->response->redirect( $c->uri_for( $default_home_page ) );
}


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
