use strict;
use warnings;

package MediaWords::Test::Story;

sub new
{
    my $classname = shift;
    my $self      = {};
    return bless( $self, $classname );
}

package MediaWords::Test::API;

my $TEST_API_KEY;

use JSON;

use List::MoreUtils "uniq";
use List::Util "shuffle";

use Math::Prime::Util;

use Modern::Perl "2015";

use MediaWords;

use MediaWords::CM::Dump;

use MediaWords::CommonLibs;

use MediaWords::Pg::Schema;

use MediaWords::Test::DB;

use MediaWords::Util::Web;

use MediaWords::Controller::Api::V2::Topics::Stories;

use Readonly;

# A constant used to generate consistent orderings in test sorts
Readonly my $TEST_MODULO => 6;

BEGIN
{
    use Catalyst::Test ( 'MediaWords' );
}

use List::MoreUtils "uniq";
use LWP::UserAgent "request";

sub add_bitly_count
{
    my ( $db, $id, $story, $click_count ) = @_;
    $db->query( "insert into bitly_clicks_total values ( \$1,\$2,\$3 )", $id, $story->{ stories_id }, $click_count );
}

sub add_controversy_story
{
    my ( $db, $controversy, $story ) = @_;

    $db->create( 'controversy_stories',
        { stories_id => $story->{ stories_id }, controversies_id => $controversy->{ controversies_id } } );
}

sub create_test_api_user
{
    my $db = shift;
    $TEST_API_KEY = MediaWords::Test::DB::create_test_user( $db );
}

sub create_stories
{
    my ( $db, $stories, $controversies ) = @_;

    my $media = MediaWords::Test::DB::create_test_story_stack( $db, $stories );

}

sub add_controversy_link
{
    my ( $db, $controversy, $story, $ref_story ) = @_;

    $db->create(
        'controversy_links',
        {
            controversies_id => $controversy->{ controversies_id },
            stories_id       => $story,
            url              => 'http://foo',
            redirect_url     => 'http://foo',
            ref_stories_id   => $ref_story,
        }
    );

}

sub create_test_data
{

    my ( $test_db, $controversy_media_sources ) = @_;

    my $NUM_LINKS_PER_PAGE = 10;

    srand( 3 );

    # populate controversies table
    my $controversy = $test_db->create(
        'controversies',
        {
            name                => 'foo',
            solr_seed_query     => '',
            solr_seed_query_run => 'f',
            pattern             => '',
            description         => 'test controversy'
        }
    );

    my $controversy_dates = $test_db->create(
        'controversy_dates',
        {
            controversies_id => $controversy->{ controversies_id },
            start_date       => '2014-04-01',
            end_date         => '2014-06-01'
        }
    );

    # populate controversies_stories table
    # only include stories with id not multiples of $TEST_MODULO
    my $all_stories         = {};
    my $controversy_stories = [];

    for my $m ( values( %{ $controversy_media_sources } ) )
    {
        for my $f ( values( %{ $m->{ feeds } } ) )
        {
            while ( my ( $num, $story ) = each( %{ $f->{ stories } } ) )
            {
                if ( $num % $TEST_MODULO )
                {
                    my $cs = add_controversy_story( $test_db, $controversy, $story );
                    push @{ $controversy_stories }, $story->{ stories_id };
                }
                $all_stories->{ int( $num ) } = $story->{ stories_id };

                # modding by a different number than stories included in controversies
                # so that we will have bitly counts of 0

                add_bitly_count( $test_db, $num, $story, $num % ( $TEST_MODULO - 1 ) );
            }
        }
    }

    # populate controversies_links table
    while ( my ( $num, $story_id ) = each %{ $all_stories } )
    {
        my @factors = Math::Prime::Util::factor( $num );
        foreach my $factor ( uniq @factors )
        {
            if ( $factor != $num )
            {
                add_controversy_link( $test_db, $controversy, $all_stories->{ $factor }, $story_id );
            }
        }
    }

    MediaWords::CM::Dump::dump_controversy( $test_db, $controversy->{ controversies_id } );

}

sub call_test_api
{
    my $base_url = shift;
    my $url      = _api_request_url( $base_url->{ path }, $base_url->{ params } );
    my $response = request( $url );
}

sub _api_request_url($;$)
{
    my ( $path, $params ) = @_;
    my $uri = URI->new( $path );
    $uri->query_param( 'key' => $TEST_API_KEY );
    if ( $params )
    {
        foreach my $key ( keys %{ $params } )
        {
            $uri->query_param( $key => $params->{ $key } );
        }
    }
    return $uri->as_string;
}

1;
