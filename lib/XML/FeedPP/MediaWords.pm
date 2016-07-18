package XML::FeedPP::MediaWords;

##
#  This class is a wrapper to work around bugs in XML::FeedPP
#  XML::FeedPP does not provide a way to grab the <content> element from RSS feeds
#  It will only provide the <description> element which often has a summary instead of the full text
#
#  We wanted to sub class XML::FeedPP but XML::FeedPP cannot be subclassed so we have to use AUTOMETHOD to fake subclassing it.
#
##
use strict;
use warnings;

use Data::Dumper;
use XML::FeedPP;

use Class::Std;
{

    my %feedPP : ATTR;

    sub BUILD
    {
        my ( $self, $ident, $arg_ref ) = @_;

        my $content = $arg_ref->{ content };
        my $type    = $arg_ref->{ type };

        my $fp;

        my $snapshot_content = 0;
        my $snapshot_file    = '/tmp/content.txt';

        $DB::single = 1;

        if ( $snapshot_content )
        {

            open OUTFILE, ">", $snapshot_file;

            say OUTFILE $content;

            close OUTFILE;

            # say STDERR Dumper ( { content -> $content,
            # 		      type -> $type,
            # 		      } );
        }

        eval { $fp = XML::FeedPP->new( $content, -type => $type ); };

        $feedPP{ $ident } = $fp;

        if ( $@ )
        {
            my $err_mesg = $@;
            die "XML::FeedPP->new failed: $err_mesg";
        }
    }

    sub _wrapper_if_necessary
    {
        my ( $obj ) = @_;

        return $obj if ( !$obj->isa( 'XML::FeedPP::RSS::Item' ) );

        return XML::FeedPP::RSS::Item::MediaWords->create_wrapped_rss_item( $obj );
    }

    sub get_item
    {
        my $self = shift;

        my @args  = @_;
        my @items = $feedPP{ ident $self}->get_item( @args );

        my @ret = map { _wrapper_if_necessary( $_ ) } @items;

        if ( defined( $args[ 0 ] ) )
        {
            return $ret[ 0 ];
        }
        elsif ( wantarray )
        {
            return @ret;
        }
        else
        {
            return scalar @ret;
        }
    }

    sub AUTOMETHOD
    {
        my ( $self, $ident, $number ) = @_;

        my $subname = $_;    # Requested subroutine name is passed via $_

        return sub { return $feedPP{ ident $self}->$subname; };
    }
}

1;

package XML::FeedPP::RSS::Item::MediaWords;

use base 'XML::FeedPP::RSS::Item';

use Data::Dumper;

sub create_wrapped_rss_item
{
    my $package = shift;
    my $obj     = shift;

    my $debug = Dumper( $obj );

    #say $debug;

    bless $obj, $package;

    return $obj;
}

sub description
{
    my $self = shift;

    my $description = $self->SUPER::description( @_ );

    my $content;
    $content = $self->get( 'content:encoded' );

    return $content || $description;
}

sub guid
{
    my $self = shift;

    my $guid = $self->SUPER::guid( @_ );

    if ( $guid && ref $guid )
    {

        #WORK AROUND FOR NASTY in XML::Feed
        if ( ( ref $guid ) eq 'HASH' )
        {
            undef( $guid );
        }
    }

    return $guid;
}

1;
