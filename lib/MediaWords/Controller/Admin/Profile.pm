package MediaWords::Controller::Admin::Profile;

use strict;
use warnings;

use Moose;
use namespace::autoclean;

use MediaWords::Util::Config;
use MediaWords::DBI::Auth;

use List::MoreUtils qw/ any /;

BEGIN { extends 'Catalyst::Controller'; }

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    # Fetch readonly information about the user
    my $userinfo = MediaWords::DBI::Auth::user_info( $c->dbis, $c->user->username );
    my $userauth = MediaWords::DBI::Auth::user_auth( $c->dbis, $c->user->username );
    unless ( $userinfo and $userauth )
    {
        die 'Unable to find currently logged in user in the database.';
    }
    my $roles = $userauth->{ roles };

    my $weekly_requests_limit        = $userinfo->{ weekly_requests_limit } + 0;
    my $weekly_requested_items_limit = $userinfo->{ weekly_requested_items_limit } + 0;

    # Admin users are effectively unlimited
    my $roles_exempt_from_user_limits = MediaWords::DBI::Auth::roles_exempt_from_user_limits();
    foreach my $exempt_role ( @{ $roles_exempt_from_user_limits } )
    {
        if ( any { $exempt_role } @{ $roles } )
        {
            $weekly_requests_limit        = 0;
            $weekly_requested_items_limit = 0;
        }
    }

    # Prepare the template
    $c->stash->{ c }         = $c;
    $c->stash->{ email }     = $userinfo->{ email };
    $c->stash->{ full_name } = $userinfo->{ full_name };
    $c->stash->{ api_token } = $userinfo->{ api_token };
    $c->stash->{ notes }     = $userinfo->{ notes };

    $c->stash->{ weekly_requests_sum }          = $userinfo->{ weekly_requests_sum } + 0;
    $c->stash->{ weekly_requested_items_sum }   = $userinfo->{ weekly_requested_items_sum } + 0;
    $c->stash->{ weekly_requests_limit }        = $weekly_requests_limit;
    $c->stash->{ weekly_requested_items_limit } = $weekly_requested_items_limit;

    $c->stash( template => 'auth/profile.tt2' );

    # Prepare the "change password" form
    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/auth/changepass.yml',
            method           => 'POST',
            action           => $c->uri_for( '/admin/profile' ),
        }
    );

    $form->process( $c->request );
    unless ( $form->submitted_and_valid() )
    {

        # No change password attempt
        $c->stash->{ form } = $form;
        return;
    }

    # Change the password
    my $password_old        = $form->param_value( 'password_old' );
    my $password_new        = $form->param_value( 'password_new' );
    my $password_new_repeat = $form->param_value( 'password_new_repeat' );

    my $error_message =
      MediaWords::DBI::Auth::change_password_via_profile_or_return_error_message( $c->dbis, $c->user->username,
        $password_old, $password_new, $password_new_repeat );
    if ( $error_message ne '' )
    {
        $c->stash->{ form } = $form;
        $c->stash( error_msg => $error_message );
    }
    else
    {
        $c->stash->{ form } = $form;
        $c->stash( status_msg => "Your password has been changed. An email was sent to " .
              "'" . $c->user->username . "' to inform you about this change." );
    }
}

# regenerate API token
sub regenerate_api_token : Local
{
    my ( $self, $c ) = @_;

    # Fetch readonly information about the user
    my $userinfo = MediaWords::DBI::Auth::user_info( $c->dbis, $c->user->username );
    if ( !$userinfo )
    {
        die 'Unable to find currently logged in user in the database.';
    }

    my $email = $c->user->username;

    # Delete user
    my $regenerate_api_token_error_message =
      MediaWords::DBI::Auth::regenerate_api_token_or_return_error_message( $c->dbis, $email );
    if ( $regenerate_api_token_error_message )
    {
        $c->response->redirect( $c->uri_for( '/admin/profile', { error_msg => $regenerate_api_token_error_message } ) );
        return;
    }

    $c->response->redirect( $c->uri_for( '/admin/profile', { status_msg => "API token has been regenerated." } ) );

}

__PACKAGE__->meta->make_immutable;

1;
