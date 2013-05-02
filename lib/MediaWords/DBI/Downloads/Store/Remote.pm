package MediaWords::DBI::Downloads::Store::Remote;

# class for storing / loading downloads in remote locations via HTTP

use strict;
use warnings;

use Moose;
with 'MediaWords::DBI::Downloads::Store';

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use HTTP::Request;
use LWP::UserAgent;
use Carp;

# Constructor
sub BUILD
{
    my ( $self, $args ) = @_;

    # say STDERR "New remote download storage.";
}

# Moose method
sub store_content($$$$)
{
    my ( $self, $db, $download, $content_ref ) = @_;

    croak 'Not implemented.';

    return '';
}

# Moose method
sub fetch_content($$)
{
    my ( $self, $download ) = @_;

    my $ua = LWP::UserAgent->new;

    if ( !defined( $download->{ downloads_id } ) )
    {
        return \"";
    }

    my $username = MediaWords::Util::Config::get_config->{ mediawords }->{ fetch_remote_content_user };
    my $password = MediaWords::Util::Config::get_config->{ mediawords }->{ fetch_remote_content_password };
    my $url      = MediaWords::Util::Config::get_config->{ mediawords }->{ fetch_remote_content_url };

    if ( !$username || !$password || !$url )
    {
        die( "mediawords:fetch_remote_content_username, _password, and _url must all be set" );
    }

    if ( $url !~ /\/$/ )
    {
        $url = "$url/";
    }

    my $request = HTTP::Request->new( 'GET', $url . $download->{ downloads_id } );
    $request->authorization_basic( $username, $password );

    my $response = $ua->request( $request );

    if ( $response->is_success() )
    {
        my $content = $response->decoded_content();

        return \$content;
    }
    else
    {
        warn( "error fetching remote content for download " . $download->{ downloads_id } . " with url '$url'  " . ":\n" .
              $response->as_string );
        return \"";
    }
}

no Moose;    # gets rid of scaffolding

1;
