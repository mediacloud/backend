package MediaWords::Test::LocalServer;

use HTTP::Daemon;
use HTTP::Status;

use Data::Dumper;
use File::Temp;

sub replace_relative_urls_in_file
{
    my ( $base_url, $requested_file_path ) = @_;

    ( $fh, $modified_file_path ) = File::Temp::tmpnam();

    open( REQUESTED_FILE, "<$requested_file_path" ) || return $requested_file_path;

    while ( <REQUESTED_FILE> )
    {
        my $line = $_;
        $line =~ s/<BASE_WEBSITE_URL\/>/$base_url/;
        print $fh $line;
    }

    close( $fh );
    return $modified_file_path;
}

sub start_server
{
    my ( $web_directory ) = @_;

    my $d = HTTP::Daemon->new( ReuseAddr => 1 ) || die;

    my $url = $d->url;
    print "Daemon <URL:", $url, ">\n";

    if ( fork() != 0 )
    {
        return $url;
    }

    while ( my $c = $d->accept )
    {

        while ( my $r = $c->get_request )
        {
            my $path = $r->uri->path;
            print "path is '$path'\n";
            if ( $r->method eq 'GET' && $path && $path !~ /\.\./ )
            {

                #change double slash to single slash
                $path =~ s/^\/\//\//;

                print "path is '$path'\n";
                if ( $path eq '/kill_server' )
                {
                    $c->send_response( "shutting down" );
                    $c->close;
                    undef( $c );
                    print "Shutting down server\n";
                    exit;
                }

                $path = "$web_directory/$path";

                if ( $path =~ /\.rss$/ )
                {
                    $path = replace_relative_urls_in_file( $url, $path );
                }

                print "Sending file $path\n";
                $c->send_file_response( $path ) || die "''$!' $@' '$?'";
                print "Sent file $path\n";
            }
            else
            {
                print( $r->uri->path );
                print Dumper( $r );
                $c->send_error( RC_FORBIDDEN );
            }
        }
        print "closing connection\n";
        $c->close;
        undef( $c );
    }
}

1;
