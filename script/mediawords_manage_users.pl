#!/usr/bin/env perl

# CLI user administration
#
# Usage:
#   ./script/run_with_carton.sh ./script/mediawords_manage_users.pl
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Getopt::Long qw(:config pass_through);
use Term::Prompt;
use MediaWords::DBI::Auth;
use MediaWords::Util::Config;
use Term::ReadKey;

use MediaWords;    # load Catalyst's configuration incl. the password hashing algorithm

# Helper to read passwords from CLI without showing them
# (http://stackoverflow.com/a/701234/200603 plus http://search.cpan.org/dist/TermReadKey/ReadKey.pm)
sub _read_password
{

    # Start reading the keys
    my $password = '';

    ReadMode( 2 );    # cooked mode with echo off.

    # This will continue until the Enter key is pressed (decimal value of 10)
    while ( ord( my $key = ReadKey( 0 ) ) != 10 )
    {

        # For all value of ord($key) see http://www.asciitable.com/
        if ( ord( $key ) == 127 || ord( $key ) == 8 )
        {

            # Delete / Backspace was pressed
            # 1. Remove the last char from the password
            chop( $password );

            # 2. Move the cursor back by one, print a blank character, move the cursor back by one
            print "\b \b";
        }
        elsif ( ord( $key ) < 32 )
        {

            # Do nothing with control characters
        }
        else
        {
            $password .= $key;
        }
    }

    ReadMode( 0 );    # reset the terminal once we are done

    print STDERR "\n";

    return $password;
}

# Add user; returns 0 on success, 1 on error
sub user_add($)
{
    my ( $db ) = @_;

    my $user_email       = undef;
    my $user_full_name   = '';
    my $user_notes       = '';
    my $user_is_inactive = 0;
    my $user_roles       = '';
    my $user_password    = undef;

    my Readonly $user_add_usage =
      "Usage: $0" . ' --action=add' . ' --email=jdoe@cyber.law.harvard.edu' . ' --full_name="John Doe"' .
      ' [--notes="Media Cloud developer."]' . ' [--inactive]' . ' [--roles="query-create,media-edit,stories-edit"]' .
      ' [--password="correct horse battery staple"]';

    GetOptions(
        'email=s'     => \$user_email,
        'full_name=s' => \$user_full_name,
        'notes:s'     => \$user_notes,
        'inactive'    => \$user_is_inactive,
        'roles:s'     => \$user_roles,
        'password:s'  => \$user_password
    ) or die "$user_add_usage\n";
    die "$user_add_usage\n" unless ( $user_email and $user_full_name );

    # Roles array
    my @user_roles = split( ',', $user_roles );
    my @user_role_ids;
    foreach my $user_role ( @user_roles )
    {
        my $user_role_id = MediaWords::DBI::Auth::role_id_for_role( $db, $user_role );
        if ( !$user_role_id )
        {
            say STDERR "Role '$user_role' was not found.";
            return 1;
        }

        push( @user_role_ids, $user_role_id );
    }

    # Read password if not set
    my $user_password_repeat = undef;
    if ( $user_password )
    {
        $user_password_repeat = $user_password;
    }
    else
    {
        while ( !$user_password )
        {
            print "Enter password: ";
            $user_password = _read_password();
        }
        while ( !$user_password_repeat )
        {
            print "Repeat password: ";
            $user_password_repeat = _read_password();
        }
    }

    # Add the user
    my $add_user_error_message =
      MediaWords::DBI::Auth::add_user_or_return_error_message( $db, $user_email, $user_full_name, $user_notes,
        \@user_role_ids, ( !$user_is_inactive ),
        $user_password, $user_password_repeat );
    if ( $add_user_error_message )
    {
        say STDERR "Error while trying to add user: $add_user_error_message";
        return 1;
    }

    say STDERR "User with email address '$user_email' was successfully added.";

    return 0;
}

# Modify user; returns 0 on success, 1 on error
sub user_modify($)
{
    my ( $db ) = @_;

    my $user_email        = undef;
    my $user_full_name    = undef;
    my $user_notes        = undef;
    my $user_is_active    = undef;
    my $user_is_inactive  = undef;
    my $user_roles        = undef;
    my $user_password     = undef;
    my $user_set_password = undef;

    my Readonly $user_modify_usage =
      "Usage: $0" . ' --action=modify' . ' --email=jdoe@cyber.law.harvard.edu' . ' [--full_name="John Doe"]' .
      ' [--notes="Media Cloud developer."]' . ' [--active|--inactive]' .
      ' [--roles="query-create,media-edit,stories-edit"]' . ' [--password="correct horse battery staple"|--set-password]';

    GetOptions(
        'email=s'      => \$user_email,
        'full_name:s'  => \$user_full_name,
        'notes:s'      => \$user_notes,
        'active'       => \$user_is_active,
        'inactive'     => \$user_is_inactive,
        'roles:s'      => \$user_roles,
        'password:s'   => \$user_password,
        'set-password' => \$user_set_password,
    ) or die "$user_modify_usage\n";
    die "$user_modify_usage\n" unless ( $user_email );

    # Fetch default information about the user
    my $db_user = MediaWords::DBI::Auth::user_info( $db, $user_email );
    my $db_user_roles = MediaWords::DBI::Auth::user_auth( $db, $user_email );

    unless ( $db_user and $db_user_roles )
    {
        say STDERR "Unable to find user '$user_email' in the database.";
        return 1;
    }

    # Check if anything has to be changed
    unless ( defined $user_full_name
        or defined $user_notes
        or defined $user_is_active
        or defined $user_is_inactive
        or defined $user_roles
        or defined $user_password
        or defined $user_set_password )
    {
        say STDERR "Nothing has to be changed.";
        die "$user_modify_usage\n";
    }

    # Hash with user values that should be put back into database
    my %modified_user;
    $modified_user{ email } = $user_email;

    # Overwrite the information if provided as parameters
    if ( $user_full_name )
    {
        $modified_user{ full_name } = $user_full_name;
    }
    else
    {
        $modified_user{ full_name } = $db_user->{ full_name };
    }

    if ( $user_notes )
    {
        $modified_user{ notes } = $user_notes;
    }
    else
    {
        $modified_user{ notes } = $db_user->{ notes };
    }

    if ( defined $user_is_active )
    {
        $modified_user{ active } = 1;
    }
    elsif ( defined $user_is_inactive )
    {
        $modified_user{ active } = 0;
    }
    else
    {
        $modified_user{ active } = $db_user->{ active };
    }

    # Roles array
    if ( $user_roles )
    {
        $modified_user{ roles } = [ split( ',', $user_roles ) ];
    }
    else
    {
        $modified_user{ roles } = $db_user_roles->{ roles };
    }

    my @user_role_ids;
    foreach my $user_role ( @{ $modified_user{ roles } } )
    {
        my $user_role_id = MediaWords::DBI::Auth::role_id_for_role( $db, $user_role );
        if ( !$user_role_id )
        {
            say STDERR "Role '$user_role' was not found.";
            return 1;
        }

        push( @user_role_ids, $user_role_id );
    }
    $modified_user{ role_ids } = \@user_role_ids;

    # Set / read the password (if needed)
    $modified_user{ password }        = '';
    $modified_user{ password_repeat } = '';
    if ( $user_password )
    {
        $modified_user{ password } = $modified_user{ password_repeat } = $user_password;
    }
    elsif ( $user_set_password )
    {
        while ( !$modified_user{ password } )
        {
            print "Enter password: ";
            $modified_user{ password } = _read_password();
        }
        while ( !$modified_user{ password_repeat } )
        {
            print "Repeat password: ";
            $modified_user{ password_repeat } = _read_password();
        }
    }

    # Modify (update) user
    my $update_user_error_message = MediaWords::DBI::Auth::update_user_or_return_error_message(
        $db,
        $modified_user{ email },
        $modified_user{ full_name },
        $modified_user{ notes },
        $modified_user{ role_ids },
        $modified_user{ active },
        $modified_user{ password },
        $modified_user{ password_repeat }
    );
    if ( $update_user_error_message )
    {
        say STDERR "Error while trying to modify user: $update_user_error_message";
        return 1;
    }

    say STDERR "User with email address '$user_email' was successfully modified.";

    return 0;
}

# Remove user; returns 0 on success, 1 on error
sub user_remove($)
{
    my ( $db ) = @_;

    my $user_email = undef;

    my Readonly $user_remove_usage = "Usage: $0" . ' --action=remove' . ' --email=jdoe@cyber.law.harvard.edu';

    GetOptions( 'email=s' => \$user_email, ) or die "$user_remove_usage\n";
    die "$user_remove_usage\n" unless ( $user_email );

    # Add the user
    # Delete user
    my $delete_user_error_message = MediaWords::DBI::Auth::delete_user_or_return_error_message( $db, $user_email );
    if ( $delete_user_error_message )
    {
        say STDERR "Error while trying to remove user: $delete_user_error_message";
        return 1;
    }

    say STDERR "User with email address '$user_email' was removed successfully.";

    return 0;
}

# User manager
sub main
{
    my $action        = '';                                                      # which action to take
    my @valid_actions = qw/add remove modify activate deactivate roles show/;    # valid actions

    my Readonly $usage = "Usage: $0" . ' --action=' . join( '|', @valid_actions ) . ' ...';

    GetOptions( 'action=s' => \$action, ) or die "$usage\n";
    die "$usage\n" unless ( grep { $_ eq $action } @valid_actions );

    binmode( STDOUT, ":utf8" );
    binmode( STDERR, ":utf8" );

    my $db = MediaWords::DB::connect_to_db() || die DBIx::Simple::MediaWords->error;

    if ( $action eq 'add' )
    {

        # Add user
        return user_add( $db );

    }
    elsif ( $action eq 'remove' )
    {

        # Remove user
        return user_remove( $db );
    }
    elsif ( $action eq 'modify' )
    {

        # Modify (update) user
        return user_modify( $db );
    }
}

exit main();
