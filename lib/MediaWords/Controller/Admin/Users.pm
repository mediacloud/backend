package MediaWords::Controller::Admin::Users;
use Modern::Perl "2012";
use MediaWords::CommonLibs;
use MediaWords::DBI::Auth;

use strict;
use warnings;
use parent 'Catalyst::Controller';

sub index : Path : Args(0)
{
    return list( @_ );
}

# list users
sub list : Local
{
    my ( $self, $c ) = @_;

    # Fetch list of users and roles
    my $users = MediaWords::DBI::Auth::list_of_users( $c->dbis );

    $c->stash->{ users }    = $users;
    $c->stash->{ c }        = $c;
    $c->stash->{ template } = 'users/list.tt2';
}

# confirm if the user has to be deleted
sub delete : Local
{
    my ( $self, $c ) = @_;

    my $email = $c->request->param( 'email' );
    if ( !$email )
    {
        $c->stash( error_msg => "Empty email." );
        $c->stash->{ c }        = $c;
        $c->stash->{ template } = 'users/delete.tt2';
        return;
    }

    # Fetch readonly information about the user
    my $userinfo = MediaWords::DBI::Auth::user_info( $c->dbis, $email );
    if ( !$userinfo )
    {
        die "Unable to find user '$email' in the database.";
    }

    $c->stash->{ users_id }  = $userinfo->{ users_id };
    $c->stash->{ email }     = $userinfo->{ email };
    $c->stash->{ full_name } = $userinfo->{ full_name };
    $c->stash->{ c }         = $c;
    $c->stash->{ template }  = 'users/delete.tt2';
}

# activate user
sub activate : Local
{
    my ( $self, $c ) = @_;

    my $email = $c->request->param( 'email' );
    if ( !$email )
    {
        $c->response->redirect( $c->uri_for( '/admin/users/list', { error_msg => "Empty email address." } ) );
        return;
    }

    my $activate_user_error_message = MediaWords::DBI::Auth::make_user_active( $c->dbis, $email, 1 );
    if ( $activate_user_error_message )
    {
        $c->response->redirect( $c->uri_for( '/admin/users/list', { error_msg => $activate_user_error_message } ) );
        return;
    }

    $c->response->redirect(
        $c->uri_for(
            '/admin/users/list',
            { status_msg => "User with email address '$email' has been activated and " . "now is able to login again." }
        )
    );
}

# deactivate user
sub deactivate : Local
{
    my ( $self, $c ) = @_;

    my $email = $c->request->param( 'email' );
    if ( !$email )
    {
        $c->response->redirect( $c->uri_for( '/admin/users/list', { error_msg => "Empty email address." } ) );
        return;
    }

    if ( $email eq $c->user->username )
    {
        $c->response->redirect(
            $c->uri_for( '/admin/users/list', { error_msg => "You are trying to deactivate yourself." } ) );
        return;
    }

    my $deactivate_user_error_message = MediaWords::DBI::Auth::make_user_active( $c->dbis, $email, 0 );
    if ( $deactivate_user_error_message )
    {
        $c->response->redirect( $c->uri_for( '/admin/users/list', { error_msg => $deactivate_user_error_message } ) );
        return;
    }

    $c->response->redirect(
        $c->uri_for(
            '/admin/users/list',
            { status_msg => "User with email address '$email' has been deactivated and " . "now will be unable to login." }
        )
    );
}

# delete user
sub delete_do : Local
{
    my ( $self, $c ) = @_;

    my $email = $c->request->param( 'email' );
    if ( !$email )
    {
        $c->response->redirect( $c->uri_for( '/admin/users/list', { error_msg => "Empty email address." } ) );
        return;
    }

    # Delete user
    my $delete_user_error_message = MediaWords::DBI::Auth::delete_user( $c->dbis, $email );
    if ( $delete_user_error_message )
    {
        $c->response->redirect( $c->uri_for( '/admin/users/list', { error_msg => $delete_user_error_message } ) );
        return;
    }

    # Catalyst::Authentication::Store::MediaWords checks if the user's email exists in the
    # database each and every time a page is accessed, so no need to invalidate a list of
    # user's current sessions (if any).

    $c->response->redirect(
        $c->uri_for(
            '/admin/users/list', { status_msg => "User with email address '$email' has been logged out and deleted." }
        )
    );

}

# show a new user
sub create : Local
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/users/create.yml',
            method           => 'POST',
            action           => $c->uri_for( '/admin/users/create' )
        }
    );

    # Set list of roles
    my $available_roles = MediaWords::DBI::Auth::all_roles( $c->dbis );
    my @roles_options;
    for my $role ( @{ $available_roles } )
    {
        push(
            @roles_options,
            {
                value => $role->{ roles_id },
                label => $role->{ role } . ': ' . $role->{ description }
            }
        );
    }

    my $el_roles = $form->get_element( { name => 'roles', type => 'Checkboxgroup' } );
    $el_roles->options( \@roles_options );

    $form->process( $c->request );

    $c->stash->{ form } = $form;
    $c->stash->{ c }    = $c;
    $c->stash( template => 'users/create.tt2' );

    if ( !$form->submitted_and_valid() )
    {

        # Show the form
        return;
    }

    my $user_email                        = $form->param_value( 'email' );
    my $user_full_name                    = $form->param_value( 'full_name' );
    my $user_notes                        = $form->param_value( 'notes' );
    my $user_roles                        = $form->param_array( 'roles' );
    my $user_password                     = '';
    my $user_password_repeat              = '';
    my $user_will_choose_password_himself = $form->param_value( 'password_chosen_by_user' );
    if ( $user_will_choose_password_himself )
    {

        # Choose a random password that will be never used so as not to leave the 'password'
        # field in database empty
        $user_password        = MediaWords::DBI::Auth::random_string( 64 );
        $user_password_repeat = $user_password;
    }
    else
    {
        $user_password        = $form->param_value( 'password' );
        $user_password_repeat = $form->param_value( 'password_repeat' );
    }

    # Add user
    my $add_user_error_message =
      MediaWords::DBI::Auth::add_user( $c->dbis, $user_email, $user_password, $user_password_repeat, $user_full_name,
        $user_notes, $user_roles );
    if ( $add_user_error_message )
    {
        $c->stash->{ c }    = $c;
        $c->stash->{ form } = $form;
        $c->stash( template  => 'users/create.tt2' );
        $c->stash( error_msg => $add_user_error_message );
        return;
    }

    # Send the password reset link if needed
    if ( $user_will_choose_password_himself )
    {
        my $reset_password_error_message =
          MediaWords::DBI::Auth::send_password_reset_token( $c->dbis, $user_email, $c->uri_for( '/login/reset' ) );
        if ( $reset_password_error_message )
        {
            $c->stash->{ c }    = $c;
            $c->stash->{ form } = $form;
            $c->stash( template  => 'users/create.tt2' );
            $c->stash( error_msg => $reset_password_error_message );
            return;
        }
    }

    # Reset the form except for the "user will choose his / her own password" field
    $form->default_values( { password_chosen_by_user => $user_will_choose_password_himself } );
    $form->process( {} );

    my $status_msg = '';
    if ( $user_will_choose_password_himself )
    {
        $status_msg =
          "User with email address '$user_email' has been created and the password reset " .
          "link has been sent to the email address provided.";
    }
    else
    {
        $status_msg =
          "User with email address '$user_email' has been created with the password provided. " .
          "No emails have been sent.";
    }
    $status_msg .= " You may now create another user using the form below.";

    $c->stash( status_msg => $status_msg );
    $c->stash->{ form } = $form;
    $c->stash->{ c }    = $c;
    $c->stash( template => 'users/create.tt2' );
}

1;
