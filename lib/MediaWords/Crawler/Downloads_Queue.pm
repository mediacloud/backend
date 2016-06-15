package MediaWords::Crawler::Downloads_Queue;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

# provide one request at a time a crawler process

use strict;
use warnings;

use URI::Split;
use Fcntl qw (O_RDWR O_CREAT O_TRUNC);
use File::Path;
use Data::Dumper;
use MediaWords::DB;
use MediaWords::Util::Config;
use Readonly;

#use Tie::File;
use Carp qw( croak confess );

Readonly my $DEBUG_MODE => 0;

sub new
{
    my ( $class ) = @_;

    my $self = {};
    bless( $self, $class );

    # hash of {
    #     $download_media_id => {
    #         time => $last_request_time_for_media_id,
    #         pending => $pending_downloads
    #     }
    # }
    $self->{ downloads } = {};

    $self->{ downloads_count } = 0;

    return $self;
}

sub _get_download_queue_file_name
{
    my ( $self, $media_id ) = @_;

    my $config = MediaWords::Util::Config::get_config;

    my $data_dir = $config->{ mediawords }->{ download_queue_dir } || $config->{ mediawords }->{ data_dir };

    my $queue_dir = "$data_dir/download_queues";

    File::Path::mkpath( $queue_dir );
    my $ret = "$queue_dir/$media_id";
    print "_get_download_queue_file_name returning: $ret\n";

    return $ret;
}

sub _get_media_download_queue
{
    my ( $self, $media_id ) = @_;

    my @array;

    #my $file_name = $self->_get_download_queue_file_name($media_id);
    #tie @array, 'Tie::File', $file_name , mode => O_RDWR | O_CREAT | O_TRUNC || confess "error tying array: $!";
    my $ret = \@array;

    return $ret;
}

sub get_download_site_from_hostname
{
    my ( $host_name ) = @_;

    # to improve speed, we just throttle by host name now.
    return $host_name;

    confess unless defined( $host_name );
    $host_name =~ s/.*\.([^.]*\.[^.]*)/$1/;

    return $host_name;
}

sub _queue_download
{
    my ( $self, $download ) = @_;

    my $media_id = $download->{ _media_id };

    if ( !defined( $media_id ) )
    {
        die( "missing media_id" );
    }

    $self->{ downloads }->{ $media_id }->{ queued } ||= $self->_get_media_download_queue( $media_id );
    $self->{ downloads }->{ $media_id }->{ time }   ||= 0;
    $self->{ downloads }->{ $media_id }->{ map }    ||= {};

    my $map = $self->{ downloads }->{ $media_id }->{ map };

    return if ( $map->{ $download->{ downloads_id } } );

    $map->{ $download->{ downloads_id } } = 1;

    my $pending = $self->{ downloads }->{ $media_id }->{ queued };

    if ( $download->{ priority } && ( $download->{ priority } > 0 ) )
    {
        unshift( @{ $pending }, $download );
    }
    else
    {
        push( @{ $pending }, $download );
    }

    $self->{ downloads_count }++;
}

# pop the latest download for the given media_id off the queue
sub _pop_download
{
    my ( $self, $media_id ) = @_;
    $self->{ downloads }->{ $media_id }->{ time } = time;

    $self->{ downloads }->{ $media_id }->{ queued } ||= [];

    my $download_serialized = shift( @{ $self->{ downloads }->{ $media_id }->{ queued } } );
    my $download            = $download_serialized;

    if ( $download )
    {

        # this causes a race condition which results in us redownloading a lot of
        # duplicate downloads.  The easiest thing is just to comment this line,
        # with the effect that no download can be redownloaded until the crawler
        # is restarted.  That shouldn't happen in any case unless someone is manually
        # fiddling with download rows in the database. -hal
        #$self->{ downloads }->{ $media_id }->{ map }->{ $download->{ downloads_id } } = 0;
        $self->{ downloads_count }--;
    }

    return $download;
}

# get list of download media_id times in the form of { media_id => $media_id, time => $time }
sub _get_download_media_ids
{
    my ( $self ) = @_;

    return [
        map { { media_id => $_, time => $self->{ downloads }->{ $_ }->{ time } } }
          keys( %{ $self->{ downloads } } )
    ];
}

sub _get_queued_downloads_count
{
    my ( $self, $media_id, $quiet ) = @_;

    unless ( defined( $quiet ) ) { print "_get_queued_downloads_count media='$media_id'\n"; }

    my $ret;

    if ( !defined( $self->{ downloads }->{ $media_id } ) || !$self->{ downloads }->{ $media_id } )
    {
        $ret = 0;
    }
    elsif ( !$self->{ downloads }->{ $media_id }->{ queued } )
    {
        $ret = 0;
    }
    else
    {
        $ret = scalar( @{ $self->{ downloads }->{ $media_id }->{ queued } } );
    }

    unless ( defined( $quiet ) ) { print "_get_queued_downloads_count media='$media_id' returning '$ret'\n"; }

    return $ret;
}

# sub _get_download_media_ids_under_queue_max
# {
#     my ($self, $queue_max) = @_;

#     return [ grep { scalar($_->{downloads}->{queued}) } key (%{$self->{ downloads }}) ];
# }

sub _verify_downloads_count
{
    my ( $self ) = @_;

    my $downloads_count_real = 0;

    for my $a ( values( %{ $self->{ downloads } } ) )
    {
        if ( @{ $a->{ queued } } )
        {
            $downloads_count_real += scalar( @{ $a->{ queued } } );
        }
    }

    die "\$downloads_counts is " . $self->{ downloads_count } . " but there are actually $downloads_count_real downloads"
      unless $downloads_count_real == $self->{ downloads_count };
}

# get total number of queued downloads
sub _get_downloads_size
{
    my ( $self ) = @_;

    if ( $DEBUG_MODE )
    {
        $self->_verify_downloads_count();
    }

    return $self->{ downloads_count };
}

1;
