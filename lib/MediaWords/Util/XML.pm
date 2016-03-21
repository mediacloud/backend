package MediaWords::Util::XML;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

# various functions for manipulating XML

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(xml_tree_from_hash);

use strict;
use XML::LibXML;

sub xml_tree_from_hash
{
    my ( $hash, $name ) = @_;

    my $node = XML::LibXML::Element->new( $name );

    foreach my $key ( sort keys %{ $hash } )
    {

        #say STDERR "appending '$key'  $hash->{ $key } ";

        my $key_val = $hash->{ $key };

        if ( !defined( $key_val ) )
        {
            $key_val = '';
        }

        #next if ( ( $key eq 'error_message' ) && ( ! defined (  $hash->{ $key }  ) ) );

        #die "$key not defined for hash" unless defined (  $hash->{ $key }  );

        $node->appendTextChild( $key, $key_val );
    }

    return $node;
}

1;
