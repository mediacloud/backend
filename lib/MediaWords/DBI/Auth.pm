package MediaWords::DBI::Auth;

#
# Authentication helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::DBI::Auth::Mail;
use MediaWords::Util::Text;

use Crypt::SaltedHash;
use Data::Dumper;
use Digest::SHA qw/sha256_hex/;
use Readonly;
use URI::Escape;

# Post-unsuccessful login delay (in seconds)
Readonly my $POST_UNSUCCESSFUL_LOGIN_DELAY => 1;

# Password hash type
Readonly my $PASSWORD_HASH_TYPE => 'SHA-256';

# Password salt length
Readonly my $PASSWORD_SALT_LEN => 64;

# API token HTTP GET parameter
Readonly my $API_TOKEN_PARAMETER => 'key';

# Validate a password / password token with Crypt::SaltedHash; return 1 on success, 0 on error
sub password_hash_is_valid($$)
{
    my ( $secret_hash, $secret ) = @_;

    if ( Crypt::SaltedHash->validate( $secret_hash, $secret, $PASSWORD_SALT_LEN ) )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Hash a secure hash (password / password reset token) with Crypt::SaltedHash;
# return hash on success, die() on error
sub _generate_secure_hash($)
{
    my ( $secret ) = @_;

    # Hash the password
    my $csh = Crypt::SaltedHash->new( algorithm => $PASSWORD_HASH_TYPE, salt_len => $PASSWORD_SALT_LEN );
    $csh->add( $secret );
    my $secret_hash = $csh->generate;
    unless ( $secret_hash )
    {
        LOGCONFESS "Unable to hash a secret.";
    }

    unless ( password_hash_is_valid( $secret_hash, $secret ) )
    {
        LOGCONFESS "Secret hash has been generated, but it does not validate.";
    }

    return $secret_hash;
}

# Fetch a list of available user roles
sub all_user_roles($)
{
    my ( $db ) = @_;

    my $roles = $db->query(
        <<"SQL"
        SELECT auth_roles_id,
               role,
               description
        FROM auth_roles
        ORDER BY auth_roles_id
SQL
    )->hashes;

    return $roles;
}

# Fetch a user role's ID for a role; die()s if no such role was found
sub role_id_for_role($$)
{
    my ( $db, $role ) = @_;

    if ( !$role )
    {
        LOGCONFESS "Role is empty.";
    }

    my $auth_roles_id = $db->query(
        <<"SQL",
        SELECT auth_roles_id
        FROM auth_roles
        WHERE role = ?
        LIMIT 1
SQL
        $role
    )->hash;
    if ( !( ref( $auth_roles_id ) eq ref( {} ) and $auth_roles_id->{ auth_roles_id } ) )
    {
        LOGCONFESS "Role '$role' was not found.";
    }

    return $auth_roles_id->{ auth_roles_id };
}

# Fetch a hash of basic user information (email, full name, notes); die() on error
sub user_info($$)
{
    my ( $db, $email ) = @_;

    unless ( $email )
    {
        LOGCONFESS "User email is not defined.";
    }

    # Fetch readonly information about the user
    my $userinfo = $db->query(
        <<"SQL",
        SELECT auth_users.auth_users_id,
               auth_users.email,
               full_name,
               api_token,
               notes,
               active,
               weekly_requests_sum,
               weekly_requested_items_sum,
               weekly_requests_limit,
               weekly_requested_items_limit
        FROM auth_users
            INNER JOIN auth_user_limits
                ON auth_users.auth_users_id = auth_user_limits.auth_users_id,
            auth_user_limits_weekly_usage( \$1 )
        WHERE auth_users.email = \$1
        LIMIT 1
SQL
        $email
    )->hash;
    unless ( ref( $userinfo ) eq ref( {} ) and $userinfo->{ auth_users_id } )
    {
        LOGCONFESS "User with email '$email' was not found.";
    }

    return $userinfo;
}

# Check if user is trying to log in too soon after last unsuccessful attempt to do that
# Returns 1 if too soon, 0 otherwise
sub user_is_trying_to_login_too_soon($$)
{
    my ( $db, $email ) = @_;

    my $interval = "$POST_UNSUCCESSFUL_LOGIN_DELAY seconds";

    my $user = $db->query(
        <<"SQL",
        SELECT auth_users_id,
               email
        FROM auth_users
        WHERE email = ?
              AND last_unsuccessful_login_attempt >= LOCALTIMESTAMP - INTERVAL '$interval'
        ORDER BY auth_users_id
        LIMIT 1
SQL
        $email
    )->hash;

    if ( ref( $user ) eq ref( {} ) and $user->{ auth_users_id } )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Fetch a hash of basic user information, password hash and an array of assigned roles.
# Fetches both active and deactivated users; checking whether or not the user is active is left to the controller.
# Returns 0 on error.
# This subroutine is used by Catalyst::Authentication::Store::MediaWords for authenticating users
sub user_auth($$)
{
    my ( $db, $email ) = @_;

    unless ( $email )
    {
        LOGCONFESS "User email is not defined.";
    }

    # Check if user exists; if so, fetch user info, password hash and a list of roles.
    my $user = $db->query(
        <<"SQL",
        SELECT auth_users.auth_users_id,
               auth_users.email,
               auth_users.password_hash,
               auth_users.active,
               ARRAY_TO_STRING(ARRAY_AGG(role), ' ') AS roles
        FROM auth_users
            LEFT JOIN auth_users_roles_map
                ON auth_users.auth_users_id = auth_users_roles_map.auth_users_id
            LEFT JOIN auth_roles
                ON auth_users_roles_map.auth_roles_id = auth_roles.auth_roles_id
        WHERE auth_users.email = ?
        GROUP BY auth_users.auth_users_id,
                 auth_users.email,
                 auth_users.password_hash,
                 auth_users.active
        ORDER BY auth_users.auth_users_id
        LIMIT 1
SQL
        $email
    )->hash;

    unless ( ref( $user ) eq ref( {} ) and $user->{ auth_users_id } )
    {
        LOGCONFESS "User with email '$email' was not found.";
    }

    # Make an array out of list of roles
    $user->{ roles } = [ split( ' ', $user->{ roles } ) ];

    return $user;
}

# Fetch a hash of basic user information and an array of assigned roles based on the API token.
# Only active users are fetched.
# Returns 0 on error
sub user_for_api_token($$)
{
    my ( $c, $api_token ) = @_;

    my $db         = $c->dbis;
    my $ip_address = $c->request_ip_address();

    my $user = $db->query(
        <<"SQL",
        SELECT auth_users.auth_users_id,
               auth_users.email,
               ARRAY_TO_STRING(ARRAY_AGG(role), ' ') AS roles
        FROM auth_users
            LEFT JOIN auth_users_roles_map
                ON auth_users.auth_users_id = auth_users_roles_map.auth_users_id
            LEFT JOIN auth_roles
                ON auth_users_roles_map.auth_roles_id = auth_roles.auth_roles_id
        WHERE auth_users.api_token = LOWER(\$1) OR
            LOWER(\$1) in (
                SELECT api_token
                    FROM auth_user_ip_tokens
                    WHERE
                        auth_users.auth_users_id = auth_user_ip_tokens.auth_users_id AND
                        ip_address = \$2 )
          AND active = true
        GROUP BY auth_users.auth_users_id,
                 auth_users.email
        ORDER BY auth_users.auth_users_id
        LIMIT 1
SQL
        $api_token,
        $ip_address
    )->hash;

    if ( !( ref( $user ) eq ref( {} ) and $user->{ auth_users_id } ) )
    {
        return 0;
    }

    # Make an array out of list of roles
    $user->{ roles } = [ split( ' ', $user->{ roles } ) ];

    return $user;
}

# Same as above, just with the Catalyst's $c object
sub user_for_api_token_catalyst($)
{
    my $c = shift;

    my $api_token = $c->request->param( $API_TOKEN_PARAMETER . '' );

    return user_for_api_token( $c, $api_token );
}

# Post-successful login database tasks
sub post_successful_login($$)
{
    my ( $db, $email ) = @_;

    # Reset the password reset token (if any)
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = ?
SQL
        $email
    );
}

# Post-unsuccessful login database tasks
sub post_unsuccessful_login($$)
{
    my ( $db, $email ) = @_;

    INFO "Login failed for $email, will delay any successive login attempt for $POST_UNSUCCESSFUL_LOGIN_DELAY seconds.";

    # Set the unsuccessful login timestamp
    # (TIMESTAMP 'now' returns "current transaction's start time", so using LOCALTIMESTAMP instead)
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET last_unsuccessful_login_attempt = LOCALTIMESTAMP
        WHERE email = ?
SQL
        $email
    );

    # It might make sense to sleep() here for the duration of $POST_UNSUCCESSFUL_LOGIN_DELAY seconds
    # to prevent legitimate users from trying to log in too fast.
    # However, when being actually brute-forced through multiple HTTP connections, this approach might
    # end up creating a lot of processes that would sleep() and take up memory.
    # So, let's return the error page ASAP and hope that a legitimate user won't be able to reenter
    # his / her password before the $POST_UNSUCCESSFUL_LOGIN_DELAY amount of seconds pass.
}

# Validate password reset token; returns 1 if token exists and is valid, 0 otherwise
sub password_reset_token_is_valid($$$)
{
    my ( $db, $email, $password_reset_token ) = @_;

    if ( !( $email && $password_reset_token ) )
    {
        ERROR "Email and / or password reset token is empty.";
        return 0;
    }

    # Fetch readonly information about the user
    my $password_reset_token_hash = $db->query(
        <<"SQL",
        SELECT auth_users_id,
               email,
               password_reset_token_hash
        FROM auth_users
        WHERE email = ?
        LIMIT 1
SQL
        $email
    )->hash;
    if ( !( ref( $password_reset_token_hash ) eq ref( {} ) and $password_reset_token_hash->{ auth_users_id } ) )
    {
        ERROR 'Unable to find user ' . $email . ' in the database.';
        return 0;
    }

    $password_reset_token_hash = $password_reset_token_hash->{ password_reset_token_hash };

    if ( password_hash_is_valid( $password_reset_token_hash, $password_reset_token ) )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Check if password complies with strength the requirements; returns empty
# string on valid password, error message on invalid password
sub _validate_password($$$)
{
    my ( $email, $password, $password_repeat ) = @_;

    if ( !$email )
    {
        return 'Email address is empty.';
    }

    if ( !( $password && $password_repeat ) )
    {
        return 'To set the password, please repeat the new password twice.';
    }

    if ( $password ne $password_repeat )
    {
        return 'Passwords do not match.';
    }

    if ( length( $password ) < 8 or length( $password ) > 120 )
    {
        return 'Password must be between 8 and 120 characters length.';
    }

    if ( $password eq $email )
    {
        return 'New password is your email address; don\'t cheat!';
    }

    return '';
}

# Change password; die()s on failure
sub _change_password($$$$;$)
{
    my ( $db, $email, $password_new, $password_new_repeat, $do_not_inform_via_email ) = @_;

    my $password_validation_message = _validate_password( $email, $password_new, $password_new_repeat );
    if ( $password_validation_message )
    {
        die "Unable to change password: $password_validation_message";
    }

    # Hash + validate the password
    my $password_new_hash;
    eval { $password_new_hash = _generate_secure_hash( $password_new ); };
    if ( $@ or ( !$password_new_hash ) )
    {
        die "Unable to hash a new password: $@";
    }

    # Set the password hash
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_hash = ?, active = true
        WHERE email = ?
SQL
        $password_new_hash, $email
    );

    unless ( $do_not_inform_via_email )
    {
        MediaWords::DBI::Auth::Mail::send_password_changed_email( $email );
    }
}

# Change password by entering old password; die()s on error
sub change_password_via_profile($$$$$)
{
    my ( $db, $email, $password_old, $password_new, $password_new_repeat ) = @_;

    unless ( $password_old )
    {
        die 'To change the password, please enter an old ' . 'password and then repeat the new password twice.';
    }

    if ( $password_old eq $password_new )
    {
        die 'Old and new passwords are the same.';
    }

    # Validate old password (password hash is located in $c->user->password, but fetch
    # the hash from the database again because that hash might be outdated (e.g. if the
    # password has been changed already))
    my $db_password_old = $db->query(
        <<"SQL",
        SELECT auth_users_id,
               email,
               password_hash
        FROM auth_users
        WHERE email = ?
        LIMIT 1
SQL
        $email
    )->hash;

    if ( !( ref( $db_password_old ) eq ref( {} ) and $db_password_old->{ auth_users_id } ) )
    {
        die 'Unable to find the user in the database.';
    }
    $db_password_old = $db_password_old->{ password_hash };

    # Validate the password
    unless ( password_hash_is_valid( $db_password_old, $password_old ) )
    {
        die 'Old password is incorrect.';
    }

    # Execute the change
    eval { _change_password( $db, $email, $password_new, $password_new_repeat ); };
    if ( $@ )
    {
        my $error_message = "Unable to change password: $@";
        die $error_message;
    }
}

# Change password with a password token sent by email; die()s on error
sub change_password_via_token($$$$$)
{
    my ( $db, $email, $password_reset_token, $password_new, $password_new_repeat ) = @_;

    unless ( $password_reset_token )
    {
        die 'Password reset token is empty.';
    }

    # Validate the token once more (was pre-validated in controller)
    unless ( password_reset_token_is_valid( $db, $email, $password_reset_token ) )
    {
        die 'Password reset token is invalid.';
    }

    # Execute the change
    eval { _change_password( $db, $email, $password_new, $password_new_repeat ); };
    if ( $@ )
    {
        my $error_message = "Unable to change password: $@";
        die $error_message;
    }

    # Unset the password reset token
    post_successful_login( $db, $email );
}

# Change password with a password token sent by email; die()s on error
sub activate_user_via_token($$$)
{
    my ( $db, $email, $password_reset_token ) = @_;

    unless ( $password_reset_token )
    {
        die 'Password reset token is empty.';
    }

    # Validate the token once more (was pre-validated in controller)
    unless ( password_reset_token_is_valid( $db, $email, $password_reset_token ) )
    {
        die 'Password reset token is invalid.';
    }

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
    post_successful_login( $db, $email );
}

# Fetch and return a list of users and their roles; returns an arrayref
sub all_users($)
{
    my ( $db ) = @_;

    # List a full list of roles near each user because (presumably) one can then find out
    # whether or not a particular user has a specific role faster.
    my $users = $db->query(
        <<"SQL"
        SELECT
            auth_users.auth_users_id,
            auth_users.email,
            auth_users.full_name,
            auth_users.notes,
            auth_users.active,

            -- Role from a list of all roles
            all_user_roles.role,

            -- Boolean denoting whether the user has that particular role
            ARRAY(
                SELECT r_auth_roles.role
                FROM auth_users AS r_auth_users
                    INNER JOIN auth_users_roles_map AS r_auth_users_roles_map
                        ON r_auth_users.auth_users_id = r_auth_users_roles_map.auth_users_id
                    INNER JOIN auth_roles AS r_auth_roles
                        ON r_auth_users_roles_map.auth_roles_id = r_auth_roles.auth_roles_id
                WHERE auth_users.auth_users_id = r_auth_users.auth_users_id
            ) @> ARRAY[all_user_roles.role] AS user_has_that_role

        FROM auth_users,
             (SELECT role FROM auth_roles ORDER BY auth_roles_id) AS all_user_roles

        ORDER BY auth_users.auth_users_id
SQL
    )->hashes;

    my $unique_users = {};

    # Make a hash of unique users and their rules
    for my $user ( @{ $users } )
    {
        my $auth_users_id = $user->{ auth_users_id } + 0;
        $unique_users->{ $auth_users_id }->{ 'auth_users_id' } = $auth_users_id;
        $unique_users->{ $auth_users_id }->{ 'email' }         = $user->{ email };
        $unique_users->{ $auth_users_id }->{ 'full_name' }     = $user->{ full_name };
        $unique_users->{ $auth_users_id }->{ 'notes' }         = $user->{ notes };
        $unique_users->{ $auth_users_id }->{ 'active' }        = $user->{ active };

        if ( !ref( $unique_users->{ $auth_users_id }->{ 'roles' } ) eq ref( {} ) )
        {
            $unique_users->{ $auth_users_id }->{ 'roles' } = {};
        }

        $unique_users->{ $auth_users_id }->{ 'roles' }->{ $user->{ role } } = $user->{ user_has_that_role };
    }

    $users = [];
    foreach my $auth_users_id ( sort { $a <=> $b } keys %{ $unique_users } )
    {
        push( @{ $users }, $unique_users->{ $auth_users_id } );
    }

    return $users;
}

# Add new user; $role_ids is a arrayref to an array of role IDs; die()s on error
sub add_user($$$$$$$$;$$)
{
    my ( $db, $email, $full_name, $notes, $role_ids, $is_active, $password, $password_repeat,
        $weekly_requests_limit, $weekly_requested_items_limit )
      = @_;

    INFO "Creating user with email: $email, full name: $full_name, notes: $notes, role IDs: " .
      join( ',', @{ $role_ids } ) . ", is active: $is_active, weekly_requests_limit: " .
      ( defined $weekly_requests_limit ? $weekly_requests_limit : 'default' ) . ', weekly requested items limit: ' .
      ( defined $weekly_requested_items_limit ? $weekly_requested_items_limit : 'default' );

    my $password_validation_message = _validate_password( $email, $password, $password_repeat );
    if ( $password_validation_message )
    {
        die "Provided password is invalid: $password_validation_message";
    }

    # Check if roles is an arrayref
    if ( ref $role_ids ne 'ARRAY' )
    {
        die 'List of role IDs is not an array.';
    }

    # Check if user already exists
    my $userinfo = undef;
    eval { $userinfo = user_info( $db, $email ); };
    if ( $userinfo )
    {
        die "User with email address '$email' already exists.";
    }

    # Hash + validate the password
    my $password_hash;
    eval { $password_hash = _generate_secure_hash( $password ); };
    if ( $@ or ( !$password_hash ) )
    {
        die 'Unable to hash a new password.';
    }

    # Begin transaction
    $db->begin_work;

    # Create the user
    $db->query(
        <<"SQL",
        INSERT INTO auth_users (email, password_hash, full_name, notes, active )
        VALUES (?, ?, ?, ?, ? )
SQL
        $email, $password_hash, $full_name, $notes, normalize_boolean_for_db( $is_active )
    );

    # Fetch the user's ID
    $userinfo = undef;
    eval { $userinfo = user_info( $db, $email ); };
    if ( $@ or ( !$userinfo ) )
    {
        $db->rollback;
        die "I've attempted to create the user but it doesn't exist.";
    }
    my $auth_users_id = $userinfo->{ auth_users_id };

    # Create roles
    for my $auth_roles_id ( @{ $role_ids } )
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
    if ( defined $weekly_requests_limit )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requests_limit = ?
            WHERE auth_users_id = ?
SQL
            $weekly_requests_limit, $auth_users_id
        );
    }

    if ( defined $weekly_requested_items_limit )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requested_items_limit = ?
            WHERE auth_users_id = ?
SQL
            $weekly_requested_items_limit, $auth_users_id
        );
    }

    # End transaction
    $db->commit;
}

# Update an existing user; die()s on error
# ($password and $password_repeat are optional; if not provided, the password will not be changed)
sub update_user($$$$$$;$$$$)
{
    my ( $db, $email, $full_name, $notes, $roles, $is_active, $password, $password_repeat,
        $weekly_requests_limit, $weekly_requested_items_limit )
      = @_;

    # Check if user exists
    my $userinfo;
    eval { $userinfo = user_info( $db, $email ); };
    if ( $@ or ( !$userinfo ) )
    {
        die "User with email address '$email' does not exist.";
    }

    # Begin transaction
    $db->begin_work;

    # Update the user
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET full_name = ?,
            notes = ?,
            active = ?
        WHERE email = ?
SQL
        $full_name, $notes, normalize_boolean_for_db( $is_active ), $email
    );

    if ( $password )
    {
        eval { _change_password( $db, $email, $password, $password_repeat, 1 ); };
        if ( $@ )
        {
            my $error_message = "Unable to change password: $@";

            $db->rollback;
            die $error_message;
        }
    }

    if ( defined $weekly_requests_limit )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requests_limit = ?
            WHERE auth_users_id = ?
SQL
            $weekly_requests_limit, $userinfo->{ auth_users_id }
        );
    }

    if ( defined $weekly_requested_items_limit )
    {
        $db->query(
            <<SQL,
            UPDATE auth_user_limits
            SET weekly_requested_items_limit = ?
            WHERE auth_users_id = ?
SQL
            $weekly_requested_items_limit, $userinfo->{ auth_users_id }
        );
    }

    # Update roles
    $db->query(
        <<SQL,
        DELETE FROM auth_users_roles_map
        WHERE auth_users_id = ?
SQL
        $userinfo->{ auth_users_id }
    );
    for my $auth_roles_id ( @{ $roles } )
    {
        $db->query(
            <<SQL,
            INSERT INTO auth_users_roles_map (auth_users_id, auth_roles_id) VALUES (?, ?)
SQL
            $userinfo->{ auth_users_id }, $auth_roles_id
        );
    }

    # End transaction
    $db->commit;
}

# Delete user; die()s on error
sub delete_user($$)
{
    my ( $db, $email ) = @_;

    # Check if user exists
    my $userinfo;
    eval { $userinfo = user_info( $db, $email ); };
    if ( $@ or ( !$userinfo ) )
    {
        die "User with email address '$email' does not exist.";
    }

    # Delete the user (PostgreSQL's relation will take care of 'auth_users_roles_map')
    $db->query(
        <<SQL,
        DELETE FROM auth_users
        WHERE email = ?
SQL
        $email
    );
}

# Prepare for password reset by emailing the password reset token; die()s on error
sub send_password_reset_token($$$;$)
{
    my ( $db, $email, $password_reset_link, $new_user ) = @_;

    unless ( $email )
    {
        die 'Email address is empty.';
    }
    unless ( $password_reset_link )
    {
        die 'Password reset link is empty.';
    }

    # Check if the email address exists in the user table; if not, pretend that
    # we sent the password reset link with a "success" message.
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
        # password reset token (in order to reduce the risk of timing attacks)
        $email = '';
    }

    # Generate the password reset token
    my $password_reset_token = MediaWords::Util::Text::random_string( 64 );
    unless ( length( $password_reset_token ) > 0 )
    {
        die 'Unable to generate a password reset token.';
    }

    # Hash + validate the password reset token
    my $password_reset_token_hash;
    eval { $password_reset_token_hash = _generate_secure_hash( $password_reset_token ); };
    if ( $@ or ( !$password_reset_token_hash ) )
    {
        die "Unable to hash a password reset token: $@";
    }

    # Set the password token hash in the database
    # (if the email address doesn't exist, this query will do nothing)
    $db->query(
        <<"SQL",
        UPDATE auth_users
        SET password_reset_token_hash = ?
        WHERE email = ? AND email != ''
SQL
        $password_reset_token_hash, $email
    );

    # If we didn't find an email address in the database, we return here imitating success
    # (again, due to timing attacks)
    unless ( length( $email ) > 0 )
    {
        return;
    }

    $password_reset_link =
      $password_reset_link . '?email=' . uri_escape( $email ) . '&token=' . uri_escape( $password_reset_token );
    INFO "Full password reset link: $password_reset_link";

    eval {
        if ( $new_user )
        {
            MediaWords::DBI::Auth::Mail::send_new_user_email( $email, $password_reset_link );
        }
        else
        {
            MediaWords::DBI::Auth::Mail::send_password_reset_email( $email, $password_reset_link );
        }
    };
    if ( $@ )
    {
        my $error_message = "Unable to send email to user: $@";
        die $error_message;
    }
}

# Regenerate API token; die()s on error
sub regenerate_api_token($$)
{
    my ( $db, $email ) = @_;

    unless ( $email )
    {
        die 'Email address is empty.';
    }

    # Check if user exists
    my $userinfo;
    eval { $userinfo = user_info( $db, $email ); };
    if ( $@ or ( !$userinfo ) )
    {
        die "User with email address '$email' does not exist.";
    }

    # Regenerate API token
    $db->query(
        <<SQL,
        UPDATE auth_users
        -- DEFAULT points to a generation function
        SET api_token = DEFAULT
        WHERE email = ?
SQL
        $email
    );
}

1;
