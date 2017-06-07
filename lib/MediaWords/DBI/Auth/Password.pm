package MediaWords::DBI::Auth::Password;

#
# Password validation helpers
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Crypt::SaltedHash;
use Readonly;

use MediaWords::Util::Mail;

# Password hash type
Readonly my $PASSWORD_HASH_TYPE => 'SHA-256';

# Password salt length
Readonly my $PASSWORD_SALT_LEN => 64;

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
sub generate_secure_hash($)
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

# Validate password reset token (used for both user activation and password reset)
# Returns 1 if token exists and is valid, 0 otherwise
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
sub validate_new_password($$$)
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

1;
