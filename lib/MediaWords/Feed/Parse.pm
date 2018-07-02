package MediaWords::Feed::Parse;

#
# Parse RSS / Atom feed
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Feed::Parse::SyndicatedFeed;

use XML::LibXML;

sub _fix_atom_content_element_encoding
{
    my $xml_string = shift @_;

    my $parser = XML::LibXML->new;
    my $doc;

    eval { $doc = $parser->parse_string( $xml_string ); };

    if ( $@ )
    {
        WARN "Feed string parsing failed: $@";
        return $xml_string;
    }

    my $doc_element = $doc->documentElement() || die;

    my $xpc = XML::LibXML::XPathContext->new;
    $xpc->registerNs( 'x', 'http://www.w3.org/2005/Atom' );
    my @content_nodes = $xpc->findnodes( '//x:entry/x:content', $doc_element )->get_nodelist;

    #either the feed is RSS or there is no content
    return $xml_string if scalar( @content_nodes ) == 0;

    my $fixed_content_element = 0;

    foreach my $content_node ( @content_nodes )
    {
        next if ( !$content_node->hasChildNodes() );

        my $child_nodes = $content_node->childNodes();

        my $child_node_count = $child_nodes->size;

        if ( $child_node_count == 1 )
        {
            my $first_child = $content_node->firstChild();

            next if ( $first_child->nodeType == XML_CDATA_SECTION_NODE );
            next if ( $first_child->nodeType == XML_TEXT_NODE );
        }

        my @content_node_child_list = $child_nodes->get_nodelist();

        # allow white space before CDATA_SECTION
        if ( any { $_ && $_->nodeType == XML_CDATA_SECTION_NODE } @content_node_child_list )
        {
            my @non_cdata_children = grep { $_->nodeType != XML_CDATA_SECTION_NODE } @content_node_child_list;

            if ( all { $_->nodeType == XML_TEXT_NODE } @non_cdata_children )
            {
                if ( all { $_->data =~ /\s+/ } @non_cdata_children )
                {
                    next;
                }
            }
        }

        $fixed_content_element = 1;

        my $child_nodes_string = join '', ( map { $_->toString() } ( $child_nodes->get_nodelist() ) );

        $content_node->removeChildNodes();

        my $cdata_node = XML::LibXML::CDATASection->new( $child_nodes_string );
        $content_node->appendChild( $cdata_node );
    }

    #just return the original string if we didn't need to fix anything...
    return $xml_string if !$fixed_content_element;

    my $ret = $doc->toString;

    TRACE "Returning :'$ret'";

    return $ret;
}

# Parse feed after some simple munging to correct feed formatting.
# return the MediaWords::Feed::Parse::SyndicatedFeed::Item feed object or undef if the parse failed.
sub parse_feed($;$)
{
    my ( $content, $skip_preprocessing ) = @_;

    # fix content in various ways to make sure it will parse

    my $chunk = substr( $content, 0, 1024 );

    # make sure that there's some sort of feed id in the first chunk of the file
    if ( $chunk =~ /<html/i )
    {

        TRACE "Feed not parsed -- contains '<html'";
        return undef;
    }

    if ( $chunk !~ /<(?:rss|feed|rdf)/i )
    {

        TRACE "Feed not parsed -- missing feed tag in first 1024 characters";
        return undef;
    }

    unless ( $skip_preprocessing )
    {
        # parser doesn't like files that start with comments
        $content =~ s/^<!--[^>]*-->\s*<\?/<\?/;

        # get rid of any cruft before xml tag that upsets parser
        $content =~ s/.{1,256}\<\?xml/\<\?xml/;

        $content = _fix_atom_content_element_encoding( $content );
    }

    my $feed;

    #$DB::single = 1;
    eval { $feed = MediaWords::Feed::Parse::SyndicatedFeed->new( $content ) };

    if ( $@ )
    {
        WARN "Feed parsing failed: $@";
        return undef;
    }
    else
    {
        return $feed;
    }
}

1;
