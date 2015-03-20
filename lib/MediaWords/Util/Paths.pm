package MediaWords::Util::Paths;

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use File::Spec;
use File::Basename;

#According to a question on SO, this is a the safest way to get the directory of the current script.
#See http://stackoverflow.com/questions/84932/how-do-i-get-the-full-path-to-a-perl-script-that-is-executing
my $_dirname      = dirname( __FILE__ );
my $_dirname_full = File::Spec->rel2abs( $_dirname );

sub mc_root_path
{
    my $root_path = "$_dirname_full/../../../";

    #say STDERR "Root path is $root_path";

    return $root_path;
}

sub mc_script_path
{
    my $root_path = mc_root_path();

    my $script_path = "$root_path/script";

    #say STDERR "script path is $script_path";

    return $script_path;
}

# Get the parent of this download
#
# Parameters: database connection, download hashref
# Returns: parent download hashref or undef
sub _get_parent_download($$)
{
    my ( $db, $download ) = @_;

    if ( !$download->{ parent } )
    {
        return undef;
    }

    return $db->query( "SELECT * FROM downloads WHERE downloads_id = ?", $download->{ parent } )->hash;
}

# Return a data directory (with trailing slash)
#
# Returns: data directory (e.g. data/)
sub _get_data_dir()
{
    my $config   = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_dir };
    $data_dir =~ s!/*$!/!;    # Add a trailing slash
    return $data_dir;
}

# Get the relative path (to be used within the tarball or files) to store the given download
# The path for a download is:
#     <media_id>/<year>/<month>/<day>/<hour>/<minute>[/<parent download_id>]/<download_id>[.gz]
#
# Parameters: database connection, download, (optional) skip gzipping or not
# Returns: string download path
sub get_download_path($$)
{
    my ( $db, $downloads_id ) = @_;

    my $download = $db->query( 'SELECT * FROM downloads WHERE downloads_id = ?', $downloads_id )->hash;
    unless ( $download )
    {
        die "Download $downloads_id was not found.\n";
    }

    my $feed = $db->query( "SELECT * FROM feeds WHERE feeds_id = ?", $download->{ feeds_id } )->hash;
    unless ( $feed )
    {
        die "Feed $download->{ feeds_id } for download $downloads_id was not found.\n";
    }

    my @date = ( $download->{ download_time } =~ /(\d\d\d\d)-(\d\d)-(\d\d).(\d\d):(\d\d):(\d\d)/ );

    my @path = ( sprintf( "%06d", $feed->{ media_id } ), sprintf( "%06d", $feed->{ feeds_id } ), @date );

    for ( my $p = _get_parent_download( $db, $download ) ; $p ; $p = _get_parent_download( $db, $p ) )
    {
        push( @path, $p->{ downloads_id } );
    }

    push( @path, $download->{ downloads_id } . '.gz' );

    return join( '/', @path );
}

# Return a directory to which the Tar / file downloads should be stored (with trailing slash)
#
# Returns: directory (e.g. data/content/) to which downloads will be stored
sub get_data_content_dir()
{
    my $config = MediaWords::Util::Config::get_config;
    my $data_content_dir = $config->{ mediawords }->{ data_content_dir } || _get_data_dir . 'content/';
    $data_content_dir =~ s!/*$!/!;    # Add a trailing slash
    return $data_content_dir;
}

1;
