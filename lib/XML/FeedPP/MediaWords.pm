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

use Modern::Perl "2015";
use MediaWords::CommonLibs;

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

            TRACE Dumper( { content->$content, type->$type } );
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

use strict;
use warnings;

use base 'XML::FeedPP::RSS::Item';

use Readonly;
use Data::Dumper;

Readonly my $MAX_LINK_LENGTH => 1024;
Readonly my $MAX_GUID_LENGTH => 1024;

# if $v is a scalar, return $v, else return undef.
# we need to do this to make sure we don't get a ref back from a feed object field
sub _no_ref
{
    my ( $v ) = @_;

    return ref( $v ) ? undef : $v;
}

sub create_wrapped_rss_item
{
    my $package = shift;
    my $obj     = shift;

    my $debug = Dumper( $obj );

    #say $debug;

    bless $obj, $package;

    return $obj;
}

sub title
{
    my $self = shift;

    my $title = $self->SUPER::title( @_ );

    return _no_ref( $title );
}

sub description
{
    my $self = shift;

    my $description = $self->SUPER::description( @_ );

    my $content;
    $content = $self->get( 'content:encoded' );

    return _no_ref( $content || $description );
}

sub pubDate
{
    my $self = shift;

    my $pub_date = $self->SUPER::pubDate( @_ );

    return _no_ref( $pub_date );
}

sub category
{
    my $self = shift;

    my $category = $self->SUPER::category( @_ );

    return _no_ref( $category );
}

sub author
{
    my $self = shift;

    my $author = $self->SUPER::author( @_ );

    return _no_ref( $author );
}

sub guid
{
    my $self = shift;

    my $guid = $self->SUPER::guid( @_ );

    if ( $guid )
    {
        $guid = substr( $guid, 0, $MAX_GUID_LENGTH );
    }

    return _no_ref( $guid );
}

# some guids are not in fact unique.  return the guid if it looks valid or undef if the guid looks like
# it is not unique
sub guid_if_valid
{
    my $self = shift;

    my $guid = $self->guid();

    if ( defined $guid )
    {
        # ignore it if it is a url without a number or a path
        if ( ( $guid !~ /\d/ ) && ( $guid =~ m~https?://[^/]+/?$~ ) )
        {
            $guid = undef;
        }
    }

    return $guid;
}

sub link
{
    my $self = shift;

    my $link = $self->SUPER::link( @_ ) || $self->get( 'nnd:canonicalUrl' ) || $self->guid_if_valid();
    $link = _no_ref( $link );

    if ( $link )
    {
        $link = substr( $link, 0, $MAX_LINK_LENGTH );
        $link =~ s/[\n\r\s]//g;
    }

    return $link;
}

sub get
{
    my $self = shift;

    my $value = $self->SUPER::get( @_ );

    return _no_ref( $value );
}

1;
