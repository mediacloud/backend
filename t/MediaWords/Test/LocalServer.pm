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

    my $d = HTTP::Daemon->new( ReuseAddr => 1 ) or die "Unable to start HTTP::Daemon: $!";

    my $url = $d->url;
    say STDERR "Daemon <URL: $url>";

    if ( fork() != 0 )
    {
        return $url;
    }

    while ( my $c = $d->accept )
    {

        while ( my $r = $c->get_request )
        {
            my $uri = $r->uri;

            # We use "as_string" because URL paths with two slashes (e.g.
            # "//gv/test.rss") could be interpreted as "http://gv/test.rss" by
            # the URI module
            my $path = $uri->as_string;
            say STDERR "URI path is '$path'";

            if ( $r->method eq 'GET' && $path && $path !~ /\.\./ )
            {

                #change double slash to single slash
                $path =~ s/^\/\//\//;

                say STDERR "Normalized path is '$path'";
                if ( $path eq '/kill_server' )
                {
                    $c->send_response( "shutting down" );
                    $c->close;
                    undef( $c );
                    say STDERR "Shutting down server";
                    exit;
                }

                $path = "$web_directory/$path";

                if ( $path =~ /\.rss$/ )
                {
                    $path = replace_relative_urls_in_file( $url, $path );
                }

                unless ( -f $path )
                {
                    die "File at path $path does not exist.";
                }

                say STDERR "Sending file $path...";
                $c->send_file_response( $path ) or die "Unable to send file $path: ''$!' $@' '$?'";
                say STDERR "Sent file $path";
            }
            else
            {
                say STDERR "Won't serve path: " . $r->uri->path;
                say STDERR "Request: " . Dumper( $r );
                $c->send_error( RC_FORBIDDEN );
            }
        }
        say STDERR "closing connection";
        $c->close;
        undef( $c );
    }
}

1;
