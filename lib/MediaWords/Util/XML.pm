package MediaWords::Util::XML;

use strict;
use warnings;

# various functions for manipulating XML

use Modern::Perl "2015";
use MediaWords::CommonLibs;

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(xml_tree_from_hash);

use XML::LibXML;

sub xml_tree_from_hash
{
    my ( $hash, $name ) = @_;

    my $node = XML::LibXML::Element->new( $name );

    foreach my $key ( sort keys %{ $hash } )
    {
        TRACE "appending '$key'  $hash->{ $key } ";

        my $key_val = $hash->{ $key };

        if ( !defined( $key_val ) )
        {
            $key_val = '';
        }

        $node->appendTextChild( $key, $key_val );
    }

    return $node;
}

1;
