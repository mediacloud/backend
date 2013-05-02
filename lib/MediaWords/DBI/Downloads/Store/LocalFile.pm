package MediaWords::DBI::Downloads::Store::LocalFile;

# class for storing / loading downloads in local files

use strict;
use warnings;

use Moose;
with 'MediaWords::DBI::Downloads::Store';

use Modern::Perl "2012";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use File::Path;
use File::Slurp;
use Carp;

# Constructor
sub BUILD
{
    my ( $self, $args ) = @_;

    # say STDERR "New local file download storage.";
}

sub _expand_path($)
{
    my $path = shift;

    # note redefine delimitor from '/' to '~'
    $path =~ s~^.*/(content/.*.gz)$~$1~;

    my $config = MediaWords::Util::Config::get_config;
    my $data_dir = $config->{ mediawords }->{ data_content_dir } || $config->{ mediawords }->{ data_dir };

    $data_dir = "" if ( !$data_dir );
    $path     = "" if ( !$path );
    $path     = "$data_dir/$path";

    return $path;
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

    my $path = $download->{ path };
    if ( !$download->{ path } || ( $download->{ state } ne "success" ) )
    {
        return undef;
    }

    $path = _expand_path( $path );

    my $decoded_content = '';

    if ( -f $path )
    {

        # Read file
        my $gzipped_content = read_file( $path );

        # Gunzip + decode
        $decoded_content = $self->gunzip_and_decode( \$gzipped_content, $download->{ downloads_id } );

    }
    else
    {
        $path =~ s/\.gz$/.dl/;

        # Read file
        my $content = read_file( $path );

        # Decode
        $decoded_content = Encode::decode( 'utf-8', $content );
    }

    return \$decoded_content;
}

no Moose;    # gets rid of scaffolding

1;
