package MediaWords::Crawler::BlogPageProcessor_LiveJournal;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;

# MODULES

use Data::Dumper;
use DateTime;
use Encode;
use Feed::Find;
use HTML::LinkExtractor;
use URI::Split;
use Carp;

use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;
use MediaWords::Crawler::BlogPageProcessor;

our @ISA = ( "MediaWords::Crawler::BlogPageProcessor" );

# METHODS

sub _get_page_content
{
    ( my $url ) = @_;

    my $ua = LWP::UserAgent->new;

    my $config = MediaWords::Util::Config::get_config;

    $ua->from( $config->{ mediawords }->{ owner } );
    $ua->agent( $config->{ mediawords }->{ user_agent } );

    $ua->timeout( 20 );
    $ua->max_size( 1024 * 1024 );
    $ua->max_redirect( 15 );
    $ua->env_proxy;

    print "starting get of $url\n";

    my $response = $ua->get( $url );

    die "Failed to get $url " unless $response;

    print "Finished get of $url\n";

    return $response->content;
}

sub _get_live_journal_profile_page_country
{
    my ( $response ) = @_;

    my $url = URI->new( $response->request->uri )->canonical;

    if ( $url =~ /\/$/ )
    {
        chop( $url );
    }

    die unless $url =~ /\.livejournal.com/;

    my $profile_url = $url . "/profile";

    #$profile_url =~ /\/\/profile/\/profile/s;

    my $p = HTML::LinkExtractor->new( undef, $profile_url );

    $p->strip( 1 );

    $p->parse( \_get_page_content( $profile_url ) );

    #print "Grabbing country links from $profile_url\n";

    my @country_name_links = grep { $_->{ class } eq 'country-name' } @{ $p->links };

    return unless scalar( @country_name_links ) == 1;

    #print "Successfully pulled country_name_links\n";

    my $country_name = $country_name_links[ 0 ]->{ _TEXT };
    return $country_name;
}

sub _live_journal_profile_country_is_russian
{
    my ( $response ) = @_;

    my $country_name = _get_live_journal_profile_page_country( $response );

    return $country_name eq 'Russian Federation';
}

sub is_russian
{
    my ( $self ) = @_;

    #print "IN LiveJournal is_russian\n";

    my $url = $self->{ response }->request->uri;

    return 0 if ( $url !~ /\.livejournal.com/ );

    return _live_journal_profile_country_is_russian( $self->{ response } );
}

sub new
{
    my ( $class, $download, $response ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->{ download } = $download;
    $self->{ response } = $response;

    return $self;
}

1;
