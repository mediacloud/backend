package MediaWords::Test::DB::Create;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

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

sub create_test_topic_stories($$$$)
{
    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_test_topic_stories( @_ );
    return python_deep_copy( $return_value );
}

sub create_test_topic_posts($$)
{
    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_test_topic_posts( @_ );
    return python_deep_copy( $return_value );
}

sub create_test_snapshot($$)
{
    my ( $db, $topic ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_test_snapshot( $db, $topic );
    return python_deep_copy( $return_value );
}

sub create_test_timespan
{
    my ( $db, $topic, $snapshot ) = @_;

    my $return_value = MediaWords::Test::DB::Create::PythonProxy::create_test_timespan( $db, $topic, $snapshot );
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

1;
