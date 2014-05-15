package MediaWords::Controller::Admin::Users;
use Modern::Perl "2013";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;
use MediaWords::DBI::Auth;
use JSON;
use POSIX qw(strftime);

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

    # Fetch list of users and their roles
    my $users = MediaWords::DBI::Auth::all_users( $c->dbis );

    # Fetch role descriptions
    my $roles = MediaWords::DBI::Auth::all_user_roles( $c->dbis );
    my %role_descriptions = map { $_->{ role } => $_->{ description } } @{ $roles };

    $c->stash->{ users }             = $users;
    $c->stash->{ role_descriptions } = \%role_descriptions;
    $c->stash->{ c }                 = $c;
    $c->stash->{ template }          = 'users/list.tt2';
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

    $c->stash->{ auth_users_id } = $userinfo->{ auth_users_id };
    $c->stash->{ email }         = $userinfo->{ email };
    $c->stash->{ full_name }     = $userinfo->{ full_name };
    $c->stash->{ c }             = $c;
    $c->stash->{ template }      = 'users/delete.tt2';
}

# regenerate API token
sub regenerate_api_token : Local
{
    my ( $self, $c ) = @_;

    my $email = $c->request->param( 'email' );
    if ( !$email )
    {
        $c->response->redirect( $c->uri_for( '/admin/users/list', { error_msg => "Empty email address." } ) );
        return;
    }

    # Delete user
    my $regenerate_api_token_error_message =
      MediaWords::DBI::Auth::regenerate_api_token_or_return_error_message( $c->dbis, $email );
    if ( $regenerate_api_token_error_message )
    {
        $c->response->redirect(
            $c->uri_for( '/admin/users/edit', { email => $email, error_msg => $regenerate_api_token_error_message } ) );
        return;
    }

    $c->response->redirect(
        $c->uri_for( '/admin/users/edit', { email => $email, status_msg => "API token has been regenerated." } ) );

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
    my $delete_user_error_message = MediaWords::DBI::Auth::delete_user_or_return_error_message( $c->dbis, $email );
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

# create a new user
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
    my $available_roles = MediaWords::DBI::Auth::all_user_roles( $c->dbis );
    my @roles_options;
    for my $role ( @{ $available_roles } )
    {
        push(
            @roles_options,
            {
                value => $role->{ auth_roles_id },
                label => $role->{ role } . ': ' . $role->{ description }
            }
        );
    }

    my $el_roles = $form->get_element( { name => 'roles', type => 'Checkboxgroup' } );
    $el_roles->options( \@roles_options );

    $form->default_values(
        {
            weekly_requests_limit        => MediaWords::DBI::Auth::default_weekly_requests_limit( $c->dbis ),
            weekly_requested_items_limit => MediaWords::DBI::Auth::default_weekly_requested_items_limit( $c->dbis ),

        }
    );

    $form->process( $c->request );

    $c->stash->{ form } = $form;
    $c->stash->{ c }    = $c;
    $c->stash( template => 'users/create.tt2' );

    unless ( $form->submitted_and_valid() )
    {

        # Show the form
        return;
    }

    # Form has been submitted

    my $user_email                        = $form->param_value( 'email' );
    my $user_full_name                    = $form->param_value( 'full_name' );
    my $user_notes                        = $form->param_value( 'notes' );
    my $user_is_active                    = $form->param_value( 'active' );
    my $user_roles                        = $form->param_array( 'roles' );
    my $user_weekly_requests_limit        = $form->param_value( 'weekly_requests_limit' ) + 0;
    my $user_weekly_requested_items_limit = $form->param_value( 'weekly_requested_items_limit' ) + 0;
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
      MediaWords::DBI::Auth::add_user_or_return_error_message( $c->dbis, $user_email, $user_full_name, $user_notes,
        $user_roles, $user_is_active, $user_password, $user_password_repeat, $user_weekly_requests_limit,
        $user_weekly_requested_items_limit );
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
          MediaWords::DBI::Auth::send_password_reset_token_or_return_error_message( $c->dbis, $user_email,
            $c->uri_for( '/login/reset' ) );
        if ( $reset_password_error_message )
        {
            $c->stash->{ c }    = $c;
            $c->stash->{ form } = $form;
            $c->stash( template  => 'users/create.tt2' );
            $c->stash( error_msg => $reset_password_error_message );
            return;
        }
    }

    # Reset the form except for the roles, active / passive user and the "user will choose his /
    # her own password" field because those might be reused for creating another user
    $form->default_values(
        {
            roles                   => $user_roles,
            active                  => $user_is_active,
            password_chosen_by_user => $user_will_choose_password_himself
        }
    );
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

# show the user edit form
sub edit : Local
{
    my ( $self, $c ) = @_;

    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/users/edit.yml',
            method           => 'POST',
            action           => $c->uri_for( '/admin/users/edit' )
        }
    );

    my $user_email = $c->request->param( 'email' );
    if ( !$user_email )
    {
        $c->stash( error_msg => "Empty email." );
        $c->stash->{ c }        = $c;
        $c->stash->{ form }     = $form;
        $c->stash->{ template } = 'users/edit.tt2';
        return;
    }

    # Fetch information about the user and roles
    my $userinfo = MediaWords::DBI::Auth::user_info( $c->dbis, $user_email );
    my $roles = MediaWords::DBI::Auth::user_auth( $c->dbis, $user_email );
    unless ( $userinfo and $roles )
    {
        die "Unable to find user '$user_email' in the database.";
    }

    my %user_roles = map { $_ => 1 } @{ $roles->{ roles } };

    $form->process( $c->request );

    unless ( $form->submitted_and_valid() )
    {

        # Fetch list of available roles
        my $available_roles = MediaWords::DBI::Auth::all_user_roles( $c->dbis );
        my @roles_options;
        for my $role ( @{ $available_roles } )
        {
            my $html_role_attributes = {};
            if ( exists( $user_roles{ $role->{ role } } ) )
            {
                $html_role_attributes = { checked => 'checked' };
            }

            push(
                @roles_options,
                {
                    value      => $role->{ auth_roles_id },
                    label      => $role->{ role } . ': ' . $role->{ description },
                    attributes => $html_role_attributes
                }
            );
        }

        my $el_roles = $form->get_element( { name => 'roles', type => 'Checkboxgroup' } );
        $el_roles->options( \@roles_options );

        my $el_regenerate_api_token = $form->get_element( { name => 'regenerate_api_token', type => 'Button' } );
        $el_regenerate_api_token->comment( $userinfo->{ api_token } );

        $form->default_values(
            {
                email                        => $user_email,
                full_name                    => $userinfo->{ full_name },
                notes                        => $userinfo->{ notes },
                active                       => $userinfo->{ active },
                weekly_requests_limit        => $userinfo->{ weekly_requests_limit },
                weekly_requested_items_limit => $userinfo->{ weekly_requested_items_limit }
            }
        );

        # Re-process the form
        $form->process( $c->request );

        # Show the form
        $c->stash->{ auth_users_id } = $userinfo->{ auth_users_id };
        $c->stash->{ email }         = $userinfo->{ email };
        $c->stash->{ full_name }     = $userinfo->{ full_name };
        $c->stash->{ notes }         = $userinfo->{ notes };
        $c->stash->{ active }        = $userinfo->{ active };
        $c->stash->{ c }             = $c;
        $c->stash->{ form }          = $form;
        $c->stash->{ template }      = 'users/edit.tt2';

        return;
    }

    # Form has been submitted

    my $user_full_name                    = $form->param_value( 'full_name' );
    my $user_notes                        = $form->param_value( 'notes' );
    my $user_roles                        = $form->param_array( 'roles' );
    my $user_is_active                    = $form->param_value( 'active' );
    my $user_password                     = $form->param_value( 'password' );                       # Might be empty
    my $user_password_repeat              = $form->param_value( 'password_repeat' );                # Might be empty
    my $user_weekly_requests_limit        = $form->param_value( 'weekly_requests_limit' );
    my $user_weekly_requested_items_limit = $form->param_value( 'weekly_requested_items_limit' );

    # Check if user is trying to deactivate oneself
    if ( $userinfo->{ email } eq $c->user->username and ( !$user_is_active ) )
    {
        $c->stash->{ auth_users_id } = $userinfo->{ auth_users_id };
        $c->stash->{ email }         = $userinfo->{ email };
        $c->stash->{ full_name }     = $userinfo->{ full_name };
        $c->stash->{ notes }         = $userinfo->{ notes };
        $c->stash->{ active }        = $userinfo->{ active };
        $c->stash->{ c }             = $c;
        $c->stash->{ form }          = $form;
        $c->stash->{ template }      = 'users/edit.tt2';
        $c->stash( error_msg => "You're trying to deactivate yourself!" );
        return;
    }

    # Update user
    my $update_user_error_message =
      MediaWords::DBI::Auth::update_user_or_return_error_message( $c->dbis, $user_email, $user_full_name, $user_notes,
        $user_roles, $user_is_active, $user_password, $user_password_repeat, $user_weekly_requests_limit,
        $user_weekly_requested_items_limit );
    if ( $update_user_error_message )
    {
        $c->stash->{ auth_users_id } = $userinfo->{ auth_users_id };
        $c->stash->{ email }         = $userinfo->{ email };
        $c->stash->{ full_name }     = $userinfo->{ full_name };
        $c->stash->{ notes }         = $userinfo->{ notes };
        $c->stash->{ active }        = $userinfo->{ active };
        $c->stash->{ c }             = $c;
        $c->stash->{ form }          = $form;
        $c->stash->{ template }      = 'users/edit.tt2';
        $c->stash( error_msg => $update_user_error_message );
        return;
    }

    my $status_msg = "User information for user '$user_email' has been saved.";
    if ( $user_password )
    {
        $status_msg .= " Additionaly, the user's password has been changed.";
    }

    $c->response->redirect( $c->uri_for( '/admin/users/list', { status_msg => $status_msg } ) );
}

# view usage report page
sub usage : Local
{
    my ( $self, $c ) = @_;

    my $users = MediaWords::DBI::Auth::all_users( $c->dbis );
    my $roles = MediaWords::DBI::Auth::all_user_roles( $c->dbis );

    my $query = $c->request->param( 'query' );

    $c->stash->{ query }    = $query;
    $c->stash->{ users }    = $users;
    $c->stash->{ roles }    = $roles;
    $c->stash->{ template } = 'users/usage.tt2';
}

# send back usage JSON
sub usage_json : Local
{
    my ( $self, $c ) = @_;

    my $json_response = [];

    eval {

        my $db = $c->dbis;

        my $query = $c->request->param( 'query' ) // '';

        say STDERR "query=$query";

        my $emails = [];

        # Fetch a list of emails for which we'll generate stats
        if ( $query =~ /^role=.+?$/ )
        {

            # Users that belong to a specific role
            my ( $role ) = $query =~ /^role=(.+?)$/;
            unless ( $role )
            {
                die "Role is undefined.";
            }

            say STDERR "Showing usage for users with role '$role'";

            my $db_emails = $db->query(
                <<EOF,
                SELECT email
                FROM auth_roles
                    INNER JOIN auth_users_roles_map
                        ON auth_roles.auth_roles_id = auth_users_roles_map.auth_roles_id
                    INNER JOIN auth_users
                        ON auth_users_roles_map.auth_users_id = auth_users.auth_users_id
                WHERE role = ?
EOF
                $role
            )->hashes;
            unless ( $db_emails )
            {
                die "Unable to fetch a list of emails for role '$role'.";
            }

            $emails = [ map { $_->{ email } } @{ $db_emails } ];

        }
        elsif ( $query =~ /^user=\d+?$/ )
        {

            # Specific user
            my ( $user_id ) = $query =~ /^user=(\d+?)$/;
            unless ( $user_id )
            {
                die "User ID is undefined.";
            }

            say STDERR "Showing usage for user with ID '$user_id'.";

            my $db_email = $db->query(
                <<EOF,
                SELECT email
                FROM auth_users
                WHERE auth_users_id = ?
                LIMIT 1
EOF
                $user_id
            )->hash;
            unless ( $db_email )
            {
                die "Unable to fetch email address for user ID $user_id.";
            }

            $emails = [ $db_email->{ email } ];

        }
        else
        {

            # All users
            say STDERR "Showing usage for all users.";

            my $db_emails = $db->query(
                <<EOF
                SELECT email
                FROM auth_users
EOF
            )->hashes;

            $emails = [ map { $_->{ email } } @{ $db_emails } ];
        }

        if ( scalar( @{ $emails } ) == 0 )
        {
            die "No users found for the current query.";
        }

        # Fetch aggregated statistics
        my $statistics = $db->query(
            <<EOF,
            SELECT day,
                   SUM(requests_count) AS total_requests_count,
                   SUM(requested_items_count) AS total_requested_items_count

            FROM auth_user_request_daily_counts

            WHERE email IN (??)

            GROUP BY auth_user_request_daily_counts.day
            ORDER BY auth_user_request_daily_counts.day
EOF
            @{ $emails }
        )->hashes;
        unless ( $statistics )
        {
            die "Unable to fetch statistics for emails: " . join( ', ', @{ $emails } );
        }

        $json_response = [];
        foreach my $statistics_day ( @{ $statistics } )
        {

            my $day = {
                'day'             => $statistics_day->{ day },
                'requests'        => $statistics_day->{ total_requests_count },
                'requested_items' => $statistics_day->{ total_requested_items_count }
            };
            push( @{ $json_response }, $day );
        }

        # Insert an empty "fake" record with today's date and a zero requests if
        # there were no requests logged because otherwise the chart drawing program
        # doesn't show anything
        if ( scalar( @{ $json_response } ) == 0 )
        {

            my $day = {
                'day'             => strftime( '%Y-%m-%d', localtime ),
                'requests'        => 0,
                'requested_items' => 0
            };
            push( @{ $json_response }, $day );
        }
    };

    # Report errors to JSON
    if ( $@ )
    {
        $json_response = { 'error' => $@ };
    }

    $c->response->content_type( 'application/json; charset=UTF-8' );
    $c->response->body( encode_json( $json_response ) );
}

1;
