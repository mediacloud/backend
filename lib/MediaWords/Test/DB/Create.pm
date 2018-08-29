package MediaWords::Test::DB::Create;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use File::Path;
use Readonly;
use Text::Lorem::More;

use MediaWords::DB;
use MediaWords::DBI::Auth;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use MediaWords::DB::Schema;
use MediaWords::Util::Config;
use MediaWords::Util::URL;
use MediaWords::Test::DB::Environment;

{

    package MediaWords::Test::DB::Create::PythonProxy;

    #
    # Proxy to mediawords.test.db.create; used to make return values editable
    #

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    import_python_module( __PACKAGE__, 'mediawords.test.db.create' );

    1;
}

sub create_download_for_feed($$)
{
    my ( $db, $feed ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_download_for_feed( $db, $feed );
    return python_deep_copy( $return_value );
}

sub create_test_medium($$)
{
    my ( $db, $label ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_test_medium( $db, $label );
    return python_deep_copy( $return_value );
}

sub create_test_feed($$$)
{
    my ( $db, $label, $medium ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_test_feed( $db, $label, $medium );
    return python_deep_copy( $return_value );
}

sub create_test_story($$$)
{
    my ( $db, $label, $feed ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_test_story( $db, $label, $feed );
    return python_deep_copy( $return_value );
}

sub create_test_story_stack($$)
{
    my ( $db, $data ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_test_story_stack( $db, $data );
    return python_deep_copy( $return_value );
}

sub create_test_story_stack_numerated($$$$;$)
{
    my ( $db, $num_media, $num_feeds_per_medium, $num_stories_per_feed, $label ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_test_story_stack_numerated(
        $db,                      #
        $num_media,               #
        $num_feeds_per_medium,    #
        $num_stories_per_feed,    #
        $label,                   #
    );
    return python_deep_copy( $return_value );
}

sub create_test_topic($$)
{
    my ( $db, $label ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_test_topic( $db, $label );
    return python_deep_copy( $return_value );
}

sub add_content_to_test_story($$$)
{
    my ( $db, $story, $feed ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::add_content_to_test_story( $db, $story, $feed );
    return python_deep_copy( $return_value );
}

sub add_content_to_test_story_stack($$)
{
    my ( $db, $story_stack ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::add_content_to_test_story_stack( $db, $story_stack );
    return python_deep_copy( $return_value );
}

# Create a user for temporary databases
sub create_test_user($$)
{
    my ( $db, $label ) = @_;

    my $email = $label . '@em.ail';

    eval {
        my $new_user = MediaWords::DBI::Auth::User::NewUser->new(
            email           => $email,
            full_name       => $label,
            notes           => '',
            role_ids        => [ 1 ],
            active          => 1,
            password        => 'testtest',
            password_repeat => 'testtest',
            activation_url  => '',           # user is active, no need for activation URL
        );

        MediaWords::DBI::Auth::Register::add_user( $db, $new_user );
    };
    if ( $@ )
    {
        LOGCONFESS "Adding new user failed: $@";
    }

    my $user_info = MediaWords::DBI::Auth::Info::user_info( $db, $email );
    my $api_key = $user_info->global_api_key();

    return $api_key;
}

1;
