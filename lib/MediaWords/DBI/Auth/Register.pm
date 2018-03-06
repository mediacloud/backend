package MediaWords::DBI::Auth::Register;

#
# New user registration helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Readonly;
use URI::Escape;

use MediaWords::DBI::Auth::Login;
use MediaWords::DBI::Auth::Password;
use MediaWords::DBI::Auth::Profile;
use MediaWords::DBI::Auth::User::NewUser;
use MediaWords::Util::Mail;
use MediaWords::Util::Log;
use MediaWords::Util::Text;

# Generate user activation token
# Kept in a separate subroutine for easier testing.
# Returns undef if user was not found.
sub _generate_user_activation_token($$$)
{
    my ( $db, $email, $activation_link ) = @_;

    unless ( $email )
    {
        die 'Email address is empty.';
    }
    unless ( $activation_link )
    {
        die 'Activation link is empty.';
    }

    # Check if the email address exists in the user table; if not, pretend that
    # we sent the activation link with a "success" message.
    # That way the adversary would not be able to find out which email addresses
    # are active users.
    #
    # (Possible improvement: make the script work for the exact same amount of
    # time in both cases to avoid timing attacks)
    my $user_exists = $db->query(
        <<"SQL",
        SELECT auth_users_id,
               email
        FROM auth_users
        WHERE email = ?
        LIMIT 1
SQL
        $email
    )->hash;

    if ( !( ref( $user_exists ) eq ref( {} ) and $user_exists->{ auth_users_id } ) )
    {

        # User was not found, so set the email address to an empty string, but don't
        # return just now and continue with a rather slowish process of generating a
        # activation token (in order to reduce the risk of timing attacks)
        $email = '';
    }

    # Generate the activation token
    my $activation_token = MediaWords::Util::Text::random_string( 64 );
    unless ( length( $activation_token ) > 0 )
    {
        die 'Unable to generate an activation token.';
    }

    # Hash + validate the activation token
    my $activation_token_hash;
    eval { $activation_token_hash = MediaWords::DBI::Auth::Password::generate_secure_hash( $activation_token ); };
    if ( $@ or ( !$activation_token_hash ) )
    {
        die "Unable to hash an activation token: $@";
    }

    # Set the activation token hash in the database
    # (if the email address doesn't exist, this query will do nothing)
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_reset_token_hash = ?
        WHERE email = ? AND email != ''
SQL
        $activation_token_hash, $email
    );

    if ( $email )
    {
        return $activation_link . '?email=' . uri_escape( $email ) . '&activation_token=' . uri_escape( $activation_token );
    }
    else
    {
        return undef;
    }
}

# Prepare for activation by emailing the activation token; die()s on error
sub send_user_activation_token($$$;$)
{
    my ( $db, $email, $activation_link, $subscribe_to_newsletter ) = @_;

    $subscribe_to_newsletter //= 0;

    my $full_name;

    eval {
        my $user = MediaWords::DBI::Auth::Info::user_info( $db, $email );
        $full_name = $user->full_name();
    };
    if ( $@ )
    {
        WARN "Unable to fetch user profile for user '$email'.";
        $full_name = 'Nonexistent user';
    }

    # If user was not found, send an email to a random address anyway to avoid timing attach
    $activation_link = _generate_user_activation_token( $db, $email, $activation_link );
    unless ( $activation_link )
    {
        $email           = 'nowhere@mediacloud.org';
        $activation_link = 'activation link';
    }

    eval {
        my $message = MediaWords::Util::Mail::Message::Templates::AuthActivationNeededMessage->new(
            {
                to                      => $email,
                full_name               => $full_name,
                activation_url          => $activation_link,
                subscribe_to_newsletter => $subscribe_to_newsletter,
            }
        );
        unless ( MediaWords::Util::Mail::send_email( $message ) )
        {
            die "Unable to send email message.";
        }
    };
    if ( $@ )
    {
        WARN "Unable to send activation email: $@";
        die 'The user was created, but I was unable to send you an activation email.';
    }
}

# Add new user; $role_ids is a arrayref to an array of role IDs; die()s on error
sub add_user($$)
{
    my ( $db, $new_user ) = @_;

    unless ( $new_user )
    {
        die "New user is undefined.";
    }
    unless ( ref( $new_user ) eq 'MediaWords::DBI::Auth::User::NewUser' )
    {
        die "New user is not MediaWords::DBI::Auth::User::NewUser.";
    }

    TRACE "Creating user: " . MediaWords::Util::Log::dump_terse( $new_user );

    # Check if user already exists
    my ( $user_exists ) = $db->query(
        <<"SQL",
        SELECT 1
        FROM auth_users
        WHERE email = ?
SQL
        $new_user->email()
    )->flat;
    if ( $user_exists )
    {
        die "User with email '" . $new_user->email() . "' already exists.";
    }

    # Hash + validate the password
    my $password_hash;
    eval { $password_hash = MediaWords::DBI::Auth::Password::generate_secure_hash( $new_user->password() ); };
    if ( $@ or ( !$password_hash ) )
    {
        die 'Unable to hash a new password.';
    }

    # Begin transaction
    $db->begin_work;

    # Create the user
    $db->create(
        'auth_users',
        {
            email         => $new_user->email(),
            password_hash => $password_hash,
            full_name     => $new_user->full_name(),
            notes         => $new_user->notes(),
            active        => normalize_boolean_for_db( $new_user->active() ),
        }
    );

    # Fetch the user's ID
    my $userinfo = undef;
    eval { $userinfo = MediaWords::DBI::Auth::Info::user_info( $db, $new_user->email() ); };
    if ( $@ or ( !$userinfo ) )
    {
        $db->rollback;
        die "I've attempted to create the user but it doesn't exist: $@";
    }
    my $auth_users_id = $userinfo->id();

    # Create roles
    for my $auth_roles_id ( @{ $new_user->role_ids() } )
    {
        $db->query(
            <<SQL,
            INSERT INTO auth_users_roles_map (auth_users_id, auth_roles_id)
            VALUES (?, ?)
SQL
            $auth_users_id, $auth_roles_id
        );
    }

    # Update limits (if they're defined)
    if ( defined $new_user->weekly_requests_limit() )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requests_limit = ?
            WHERE auth_users_id = ?
SQL
            $new_user->weekly_requests_limit(), $auth_users_id
        );
    }

    if ( defined $new_user->weekly_requested_items_limit() )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requested_items_limit = ?
            WHERE auth_users_id = ?
SQL
            $new_user->weekly_requested_items_limit(), $auth_users_id
        );
    }

    # Subscribe to newsletter
    if ( $new_user->subscribe_to_newsletter() )
    {
        $db->query(
            <<SQL,
            INSERT INTO auth_users_subscribe_to_newsletter (auth_users_id)
            VALUES (?)
SQL
            $auth_users_id
        );
    }

    unless ( $new_user->active() )
    {
        send_user_activation_token(
            $db, $new_user->email(),
            $new_user->activation_url(),
            $new_user->subscribe_to_newsletter()
        );
    }

    # End transaction
    $db->commit;
}

# Change password with a password token sent by email; die()s on error
sub activate_user_via_token($$$)
{
    my ( $db, $email, $activation_token ) = @_;

    unless ( $activation_token )
    {
        die 'Password reset token is empty.';
    }

    # Validate the token once more (was pre-validated in controller)
    unless ( MediaWords::DBI::Auth::Password::password_reset_token_is_valid( $db, $email, $activation_token ) )
    {
        die 'Activation token is invalid.';
    }

    $db->begin;

    # Set the password hash
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET active = TRUE
        WHERE email = ?
SQL
        $email
    );

    # Unset the password reset token
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = ?
SQL
        $email
    );

    eval {

        my $user = MediaWords::DBI::Auth::Info::user_info( $db, $email );

        my $message = MediaWords::Util::Mail::Message::Templates::AuthActivatedMessage->new(
            {
                to        => $email,
                full_name => $user->full_name(),
            }
        );
        unless ( MediaWords::Util::Mail::send_email( $message ) )
        {
            die "Unable to send email message.";
        }

    };
    if ( $@ )
    {
        $db->rollback;
        WARN "Unable to send an email about activated user: $@";
        die "Unable to send email about an activated user.";
    }

    $db->commit;
}

1;
