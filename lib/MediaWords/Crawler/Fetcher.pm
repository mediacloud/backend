package MediaWords::Crawler::Fetcher;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;

use DateTime;
use LWP::UserAgent;

use MediaWords::DB;
use DBIx::Simple::MediaWords;
use MediaWords::Util::Config;

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine( $engine );

    return $self;
}

sub do_fetch
{
    my ( $download, $dbs ) = @_;

    $download->{ download_time } = DateTime->now->datetime;
    $download->{ state }         = 'fetching';

    $dbs->update_by_id( "downloads", $download->{ downloads_id }, $download );

    my $ua     = LWP::UserAgent->new();
    my $config = MediaWords::Util::Config::get_config;

    $ua->from( $config->{ mediawords }->{ owner } );
    $ua->agent( $config->{ mediawords }->{ user_agent } );
    $ua->cookie_jar( {} );

    $ua->timeout( 20 );
    $ua->max_size( 1024 * 1024 );
    $ua->max_redirect( 15 );
    $ua->env_proxy;

    my $response = $ua->get( $download->{ url } );

    #     if (!$response->is_t )
    #     {
    #         sleep 20;
    #
    #         $response = $ua->get( $download->{url} );
    #     }
    #
    #    print STDERR "returning from fetch_download\n";
    return $response;
}

sub fetch_download
{
    my ( $self, $download ) = @_;

    my $dbs = $self->engine->dbs;

    # FIXME - need to handle redirect manually, sticking them back into the queue as downloads
    # so that the host throttling works as it should

    #print "fetcher " . $self->engine->fetcher_number . " download: " . $download->{url} . "\n";

    return do_fetch( $download, $dbs );
}

# calling engine
sub engine
{
    if ( $_[ 1 ] )
    {
        $_[ 0 ]->{ engine } = $_[ 1 ];
    }

    return $_[ 0 ]->{ engine };
}

1;
