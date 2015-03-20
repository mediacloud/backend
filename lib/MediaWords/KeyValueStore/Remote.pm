package MediaWords::KeyValueStore::Remote;

# class for storing / loading objects (raw downloads, CoreNLP annotator results, ...) to / from remote locations via HTTP

use strict;
use warnings;

use Moose;
with 'MediaWords::KeyValueStore';

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use HTTP::Request;
use LWP::UserAgent;
use Carp;

# Configuration
has '_conf_url'      => ( is => 'rw' );
has '_conf_username' => ( is => 'rw' );
has '_conf_password' => ( is => 'rw' );

# Constructor
sub BUILD($$)
{
    my ( $self, $args ) = @_;

    # Get arguments
    unless ( $args->{ url } )
    {
        die "Please provide 'url' argument.\n";
    }
    my $url = $args->{ url };
    if ( $url !~ /\/$/ )
    {
        $url = "$url/";
    }

    unless ( $args->{ username } )
    {
        die "Please provide 'username' argument.\n";
    }
    my $username = $args->{ username };

    unless ( $args->{ password } )
    {
        die "Please provide 'password' argument.\n";
    }
    my $password = $args->{ password };

    # Store configuration
    $self->_conf_url( $url );
    $self->_conf_username( $username );
    $self->_conf_password( $password );
}

# Moose method
sub store_content($$$$)
{
    my ( $self, $db, $object_id, $content_ref ) = @_;

    die "Not implemented.\n";

    return 0;
}

# Moose method
sub fetch_content($$$;$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    my $ua = LWP::UserAgent->new;

    if ( defined $object_id )
    {
        die "Object ID is undefined.\n";
        return undef;
    }

    my $request = HTTP::Request->new( 'GET', $self->_conf_url . $object_id );
    $request->authorization_basic( $self->_conf_username, $self->_conf_password );

    my $response = $ua->request( $request );

    if ( $response->is_success() )
    {
        my $content = $response->decoded_content();

        return \$content;
    }
    else
    {
        die "Error fetching remote content for object ID $object_id with URL '" .
          $self->_conf_url . "'  " . ":\n" . $response->as_string;
        return undef;
    }
}

# Moose method
sub remove_content($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    die "Not sure how to remove remote content for object ID $object_id.\n";

    return 0;
}

# Moose method
sub content_exists($$$$)
{
    my ( $self, $db, $object_id, $object_path ) = @_;

    die "Not sure how to check whether inline content exists for object ID $object_id.\n";

    return 0;
}

no Moose;    # gets rid of scaffolding

1;
