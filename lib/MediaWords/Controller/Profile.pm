package MediaWords::Controller::Profile;
use Moose;
use namespace::autoclean;
use Crypt::SaltedHash;
use Email::MIME;
use Email::Sender::Simple qw(sendmail);

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

MediaWords::Controller::Profile - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=cut

=head2 index

Profile

=cut

# Change password; returns error message on failure, empty string on success
sub _change_password
{
    my ( $self, $c, $password_old, $password_new, $password_new_repeat ) = @_;

    my $email = $c->user->username;
    my $dbis  = $c->dbis;

    if ( !( $password_old && $password_new && $password_new_repeat ) )
    {
        return 'To change the password, please enter an old ' . 'password and then repeat the new password twice.';
    }

    if ( $password_new ne $password_new_repeat )
    {
        return 'Passwords do not match.';
    }

    if ( $password_old eq $password_new )
    {
        return 'Old and new passwords are the same.';
    }

    if ( length( $password_new ) < 8 or length( $password_new ) > 120 )
    {
        return 'Password must be 8 to 120 characters in length.';
    }

    if ( $password_new eq $email )
    {
        return 'New password is your email address; don\'t cheat!';
    }

    # Validate old password (password hash is located in $c->user->password, but fetch
    # the hash from the database again because that hash might be outdated (e.g. if the
    # password has been changed already))
    my $db_password_old = $dbis->query(
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

    my $salt_len = $c->config->{ 'Plugin::Authentication' }->{ 'users' }->{ 'credential' }->{ 'password_salt_len' };
    if ( !$salt_len )
    {
        $salt_len = 0;
    }

    my $hash_type = $c->config->{ 'Plugin::Authentication' }->{ 'users' }->{ 'credential' }->{ 'password_hash_type' };
    if ( !$hash_type )
    {
        return 'Unable to determine the password hashing algorithm.';
    }

    if ( !Crypt::SaltedHash->validate( $db_password_old, $password_old, $salt_len ) )
    {
        return 'Old password is incorrect.';
    }

    # Hash the password
    my $csh = Crypt::SaltedHash->new( algorithm => $hash_type, salt_len => $salt_len );
    $csh->add( $password_new );
    my $password_new_hash = $csh->generate;
    if ( !$password_new_hash )
    {
        return 'Unable to hash a new password.';
    }
    if ( !Crypt::SaltedHash->validate( $password_new_hash, $password_new, $salt_len ) )
    {
        return 'New password hash has been generated, but it does not validate.';
    }

    # Set the password
    $dbis->query(
        <<"EOF",
        UPDATE auth_users
        SET password_hash = ?
        WHERE email = ?
EOF
        $password_new_hash, $email
    );

    # Send email
    my $config  = MediaWords::Util::Config::get_config;
    my $message = Email::MIME->create(
        header_str => [
            From    => $config->{ mediawords }->{ email_from_address },
            To      => $email,
            Subject => '[Media Cloud] Your password has been changed',
        ],
        attributes => {
            encoding => 'quoted-printable',
            charset  => 'UTF-8',
        },
        body_str => <<"EOF"
Hello,

Your Media Cloud password has been changed.

If you made this change, no need to reply - you're all set.

If you did not request this change, please contact Media Cloud support at
www.mediacloud.org.

EOF
    );

    # send the message
    sendmail( $message );

    # Success
    return '';
}

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    # Fetch readonly information about the user
    my $dbis     = $c->dbis;
    my $userinfo = $dbis->query(
        <<"EOF",
        SELECT users_id,
               email,
               full_name,
               notes
        FROM auth_users
        WHERE email = ?
        LIMIT 1
EOF
        $c->user->username
    )->hash;
    if ( !( ref( $userinfo ) eq 'HASH' and $userinfo->{ users_id } ) )
    {
        die 'Unable to find the user in the database.';
    }

    # Prepare the template
    $c->stash->{ c }         = $c;
    $c->stash->{ email }     = $c->user->username;
    $c->stash->{ full_name } = $userinfo->{ full_name };
    $c->stash->{ notes }     = $userinfo->{ notes };
    $c->stash( template => 'auth/profile.tt2' );

    # Prepare the "change password" form
    my $form = $c->create_form(
        {
            load_config_file => $c->path_to() . '/root/forms/auth/changepass.yml',
            method           => 'POST',
            action           => $c->uri_for( '/profile' ),
        }
    );

    $form->process( $c->request );
    if ( !$form->submitted_and_valid() )
    {

        # No change password attempt
        $c->stash->{ form } = $form;
        return;
    }

    # Change the password
    my $password_old        = $form->param_value( 'password_old' );
    my $password_new        = $form->param_value( 'password_new' );
    my $password_new_repeat = $form->param_value( 'password_new_repeat' );

    my $error_message = $self->_change_password( $c, $password_old, $password_new, $password_new_repeat );
    if ( $error_message ne '' )
    {
        $c->stash->{ form } = $form;
        $c->stash( error_msg => $error_message );
    }
    else
    {
        $c->stash->{ form } = $form;
        $c->stash( status_msg => "Your password has been changed. An email was sent to " . "'" . $c->user->username .
              "' to inform you about this change." );
    }
}

=head1 AUTHOR

Linas Valiukas

=head1 LICENSE

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

__PACKAGE__->meta->make_immutable;

1;
