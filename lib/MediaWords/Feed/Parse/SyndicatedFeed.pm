package MediaWords::Feed::Parse::SyndicatedFeed;

#
# Feed parsing helper
#
# Wrapper around XML::FeedPP.
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use XML::FeedPP;
use Date::Parse;

{

    package MediaWords::Feed::Parse::SyndicatedFeed::Item;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;

    use MediaWords::Util::SQL;

    use Readonly;

    Readonly my $MAX_LINK_LENGTH => 1024;
    Readonly my $MAX_GUID_LENGTH => 1024;

    sub new($$)
    {
        my ( $class, $item ) = @_;

        unless ( $item )
        {
            die "Item is empty.";
        }
        unless ( ref( $item ) =~ /^XML::FeedPP/i )
        {
            die "Item doesn't seem to be coming from XML::FeedPP.";
        }

        my $self = {};
        bless $self, $class;

        $self->{ _item } = $item;

        return $self;
    }

    # if $v is a scalar, return $v, else return undef.
    # we need to do this to make sure we don't get a ref back from a feed object field
    sub _no_ref
    {
        my ( $v ) = @_;

        return ref( $v ) ? undef : $v;
    }

    sub title
    {
        my $self = shift;

        my $title = $self->{ _item }->title( @_ );

        return _no_ref( $title );
    }

    # XML::FeedPP does not provide a way to grab the <content> element from RSS
    # feeds.
    # It will only provide the <description> element which often has a summary
    # instead of the full text.
    sub description
    {
        my $self = shift;

        my $description = $self->{ _item }->description( @_ );

        my $content;
        $content = $self->get( 'content:encoded' );

        return _no_ref( $content || $description );
    }

    sub pubDate
    {
        my $self = shift;

        my $pub_date = $self->{ _item }->pubDate( @_ );

        return _no_ref( $pub_date );
    }

    sub publish_date_sql
    {
        my $self = shift;

        my $publish_date;

        if ( my $date_string = $self->pubDate() )
        {
            # Date::Parse is more robust at parsing date than postgres
            eval { $publish_date = MediaWords::Util::SQL::get_sql_date_from_epoch( Date::Parse::str2time( $date_string ) ); };
            if ( $@ )
            {
                WARN "Error getting date from item pubDate ('$date_string'): $@";
                $publish_date = undef;
            }
        }

        return $publish_date;
    }

    sub guid
    {
        my $self = shift;

        my $guid = $self->{ _item }->guid( @_ );

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

        my $link = $self->{ _item }->link( @_ ) || $self->get( 'nnd:canonicalUrl' ) || $self->guid_if_valid();
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

        my $value = $self->{ _item }->get( @_ );

        return _no_ref( $value );
    }

    1;
}

sub new($$)
{
    my ( $class, $feed_string ) = @_;

    unless ( $feed_string )
    {
        die "Feed string is empty.";
    }

    my $self = {};
    bless $self, $class;

    my $feed_parser;
    eval { $feed_parser = XML::FeedPP->new( $feed_string, -type => 'string' ); };
    if ( $@ )
    {
        die "XML::FeedPP->new failed: $@";
    }
    $self->{ _feed_parser } = $feed_parser;

    my @items;
    foreach my $item ( $feed_parser->get_item )
    {
        my $wrappered_item = MediaWords::Feed::Parse::SyndicatedFeed::Item->new( $item );
        push( @items, $wrappered_item );
    }
    $self->{ _items } = \@items;

    return $self;
}

#
# Add proxy subroutines to other methods as needed
#

# Returns feed title
sub title($)
{
    my $self = shift;
    return $self->{ _feed_parser }->title() . '';
}

# Returns feed items (MediaWords::Feed::Parse::SyndicatedFeed::Item objects)
sub items($)
{
    my $self = shift;
    return $self->{ _items };
}

1;
