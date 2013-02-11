package MediaWords::Controller::Admin::Profile;
use Moose;
use namespace::autoclean;
use MediaWords::DBI::Auth;

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

sub index : Path : Args(0)
{
    my ( $self, $c ) = @_;

    # Fetch readonly information about the user
    my $userinfo = MediaWords::DBI::Auth::user_info( $c->dbis, $c->user->username );
    if ( !$userinfo )
    {
        die 'Unable to find currently logged in user in the database.';
    }

    # Prepare the template
    $c->stash->{ c }         = $c;
    $c->stash->{ email }     = $userinfo->{ email };
    $c->stash->{ full_name } = $userinfo->{ full_name };
    $c->stash->{ notes }     = $userinfo->{ notes };
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

    my $error_message =
      MediaWords::DBI::Auth::change_password_via_profile( $c->dbis, $c->user->username, $password_old, $password_new,
        $password_new_repeat );
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
