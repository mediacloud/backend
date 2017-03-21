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

1;
