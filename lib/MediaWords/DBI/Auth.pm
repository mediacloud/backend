package MediaWords::DBI::Auth;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

#
# Authentication helpers
#

use strict;
use warnings;

use Digest::SHA qw/sha256_hex/;
use Crypt::SaltedHash;
use MediaWords::Util::Mail;
use POSIX qw(strftime);
use URI::Escape;

use Data::Dumper;

# Generate random alphanumeric string (password or token) of the specified length
sub _random_string($)
{
    my ( $num_bytes ) = @_;
    return join '', map +( 0 .. 9, 'a' .. 'z', 'A' .. 'Z' )[ rand( 10 + 26 * 2 ) ], 1 .. $num_bytes;
}

# Validate a password / password token with Crypt::SaltedHash; return 1 on success, 0 on error
sub _validate_hash($$)
{
    my ( $secret_hash, $secret ) = @_;

    # Determine salt (hash type should be placed in the hash)
    my $config = MediaWords::Util::Config::get_config;

    my $salt_len = $config->{ 'Plugin::Authentication' }->{ 'users' }->{ 'credential' }->{ 'password_salt_len' };
    if ( !$salt_len )
    {
        say STDERR "Salt length is 0";
        $salt_len = 0;
    }

    if ( Crypt::SaltedHash->validate( $secret_hash, $secret, $salt_len ) )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Hash a password / password token with Crypt::SaltedHash; return hash on success, empty string on error
sub _generate_hash($)
{
    my ( $secret ) = @_;

    # Determine salt and hash type
    my $config = MediaWords::Util::Config::get_config;

    my $salt_len = $config->{ 'Plugin::Authentication' }->{ 'users' }->{ 'credential' }->{ 'password_salt_len' };
    if ( !$salt_len )
    {
        say STDERR "Salt length is 0";
        $salt_len = 0;
    }

    my $hash_type = $config->{ 'Plugin::Authentication' }->{ 'users' }->{ 'credential' }->{ 'password_hash_type' };
    if ( !$hash_type )
    {
        say STDERR "Unable to determine the password hashing algorithm";
        return 0;
    }

    # Hash the password
    my $csh = Crypt::SaltedHash->new( algorithm => $hash_type, salt_len => $salt_len );
    $csh->add( $secret );
    my $secret_hash = $csh->generate;
    if ( !$secret_hash )
    {
        die "Unable to hash a secret.";
    }
    if ( !_validate_hash( $secret_hash, $secret ) )
    {
        say STDERR "Secret hash has been generated, but it does not validate.";
        return 0;
    }

    return $secret_hash;
}

# Fetch a hash of basic user information (email, full name, notes)
sub user_info($$)
{
    my ( $db, $email ) = @_;

    # Fetch readonly information about the user
    my $userinfo = $db->query(
        <<"EOF",
        SELECT users_id,
               email,
               full_name,
               notes
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $email
    )->hash;
    if ( !( ref( $userinfo ) eq 'HASH' and $userinfo->{ users_id } ) )
    {
        return 0;
    }

    return $userinfo;
}

# Post-successful login database tasks
sub post_successful_login($$)
{
    my ( $db, $email ) = @_;

    # Reset the password reset token (if any)
    $db->query(
        <<"EOF",
        UPDATE auth_users
        SET password_reset_token_hash = NULL
        WHERE email = ?
EOF
        $email
    );

    return 1;
}

# Validate password reset token; returns 1 if token exists and is valid, 0 otherwise
sub validate_password_reset_token($$$)
{
    my ( $db, $email, $password_reset_token ) = @_;

    if ( !( $email && $password_reset_token ) )
    {
        say STDERR "Email and / or password reset token is empty.";
        return 0;
    }

    # Fetch readonly information about the user
    my $password_reset_token_hash = $db->query(
        <<"EOF",
        SELECT users_id,
               email,
               password_reset_token_hash
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $email
    )->hash;
    if ( !( ref( $password_reset_token_hash ) eq 'HASH' and $password_reset_token_hash->{ users_id } ) )
    {
        say STDERR 'Unable to find user ' . $email . ' in the database.';
        return 0;
    }

    $password_reset_token_hash = $password_reset_token_hash->{ password_reset_token_hash };

    if ( _validate_hash( $password_reset_token_hash, $password_reset_token ) )
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

# Change password; returns error message on failure, empty string on success
sub _change_password($$$$)
{
    my ( $db, $email, $password_new, $password_new_repeat ) = @_;

    if ( !( $password_new && $password_new_repeat ) )
    {
        return 'To change the password, please repeat the new password twice.';
    }

    if ( $password_new ne $password_new_repeat )
    {
        return 'Passwords do not match.';
    }

    if ( length( $password_new ) < 8 or length( $password_new ) > 120 )
    {
        return 'Password must be 8 to 120 characters in length.';
    }

    if ( $password_new eq $email )
    {
        return 'New password is your email address; don\'t cheat!';
    }

    # Hash + validate the password
    my $password_new_hash = _generate_hash( $password_new );
    if ( !$password_new_hash )
    {
        return 'Unable to hash a new password.';
    }

    # Set the password hash
    $db->query(
        <<"EOF",
        UPDATE auth_users
        SET password_hash = ?
        WHERE email = ?
EOF
        $password_new_hash, $email
    );

    # Send email
    my $now           = strftime( "%a, %d %b %Y %H:%M:%S %z", localtime( time() ) );
    my $email_subject = 'Your password has been changed';
    my $email_message = <<"EOF";
Your Media Cloud password has been changed on $now.

If you made this change, no need to reply - you're all set.

If you did not request this change, please contact Media Cloud support at
www.mediacloud.org.
EOF

    if ( !MediaWords::Util::Mail::send( $email, $email_subject, $email_message ) )
    {
        return 'The password has been changed, but I was unable to send an email notifying you about the change.';
    }

    # Success
    return '';
}

# Change password by entering old password; returns error message on failure, empty string on success
sub change_password_via_profile($$$$$)
{
    my ( $db, $email, $password_old, $password_new, $password_new_repeat ) = @_;

    if ( !$password_old )
    {
        return 'To change the password, please enter an old ' . 'password and then repeat the new password twice.';
    }

    if ( $password_old eq $password_new )
    {
        return 'Old and new passwords are the same.';
    }

    # Validate old password (password hash is located in $c->user->password, but fetch
    # the hash from the database again because that hash might be outdated (e.g. if the
    # password has been changed already))
    my $db_password_old = $db->query(
        <<"EOF",
        SELECT users_id,
               email,
               password_hash
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $email
    )->hash;

    if ( !( ref( $db_password_old ) eq 'HASH' and $db_password_old->{ users_id } ) )
    {
        return 'Unable to find the user in the database.';
    }
    $db_password_old = $db_password_old->{ password_hash };

    # Validate the password
    if ( !_validate_hash( $db_password_old, $password_old ) )
    {
        return 'Old password is incorrect.';
    }

    # Execute the change
    return _change_password( $db, $email, $password_new, $password_new_repeat );
}

# Change password with a password token sent by email; returns error message on failure, empty string on success
sub change_password_via_token($$$$$)
{
    my ( $db, $email, $password_reset_token, $password_new, $password_new_repeat ) = @_;

    if ( !$password_reset_token )
    {
        return 'Password reset token is empty.';
    }

    # Validate the token once more (was pre-validated in controller)
    if ( !validate_password_reset_token( $db, $email, $password_reset_token ) )
    {
        return 'Password reset token is invalid.';
    }

    # Execute the change
    my $error_message = _change_password( $db, $email, $password_new, $password_new_repeat );
    if ( $error_message )
    {
        return $error_message;
    }

    # Unset the password reset token
    post_successful_login( $db, $email );

    return $error_message;
}

# Prepare for password reset by emailing the password reset token; returns error message on failure, empty string on success
sub send_password_reset_token($$$)
{
    my ( $db, $email, $password_reset_link ) = @_;

    if ( !$email )
    {
        return 'Email address is empty.';
    }
    if ( !$password_reset_link )
    {
        return 'Password reset link is empty.';
    }

    # Check if the email address exists in the user table; if not, pretend that
    # we sent the password reset link with a "success" message.
    # That way the adversary would not be able to find out which email addresses
    # are active users.
    #
    # (Possible improvement: make the script work for the exact same amount of
    # time in both cases to avoid timing attacks)
    my $user_exists = $db->query(
        <<"EOF",
        SELECT users_id,
               email
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $email
    )->hash;

    if ( !( ref( $user_exists ) eq 'HASH' and $user_exists->{ users_id } ) )
    {

        # User was not found, so set the email address to an empty string, but don't
        # return just now and continue with a rather slowish process of generating a
        # password reset token (in order to reduce the risk of timing attacks)
        $email = '';
    }

    # Generate the password reset token
    my $password_reset_token = _random_string( 64 );
    if ( !length( $password_reset_token ) )
    {
        return 'Unable to generate a password reset token.';
    }

    # Hash + validate the password reset token
    my $password_reset_token_hash = _generate_hash( $password_reset_token );
    if ( !$password_reset_token_hash )
    {
        return 'Unable to hash a password reset token.';
    }

    # Set the password token hash in the database
    # (if the email address doesn't exist, this query will do nothing)
    $db->query(
        <<"EOF",
        UPDATE auth_users
        SET password_reset_token_hash = ?
        WHERE email = ? AND email != ''
EOF
        $password_reset_token_hash, $email
    );

    # If we didn't find an email address in the database, we return here with a fake
    # "success" message
    if ( !length( $email ) )
    {
        return '';
    }

    $password_reset_link =
      $password_reset_link . '?email=' . uri_escape( $email ) . '&token=' . uri_escape( $password_reset_token );
    print STDERR "Full password reset link: $password_reset_link\n";

    # Send email
    my $email_subject = 'Password reset link';
    my $email_message = <<"EOF";
Someone (hopefully that was you) has requested a link to change your password,
and you can do this through the link below:

$password_reset_link

Your password won't change until you access the link above and create a new one.

If you didn't request this, please ignore this email or contact Media Cloud
support at www.mediacloud.org.
EOF

    if ( !MediaWords::Util::Mail::send( $email, $email_subject, $email_message ) )
    {
        return 'The password has been changed, but I was unable to send an email notifying you about the change.';
    }

    # Success
    return '';
}

1;
