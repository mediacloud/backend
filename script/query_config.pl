#!/usr/bin/env perl
#
# Run XPath query against Media Cloud configuration (mediawords.yml), print out
# result(s) to STDOUT (usually for piping further to other shell commands)
#
# Make sure to enclose the XPath in quotes or else you might get unexpected
# results.
#
# Usage:
#
# ./script/run_in_env.sh ./script/query_config.pl "/mediawords/session/storage"
#
# or
#
# ./script/run_in_env.sh ./script/query_config.pl "//user_agent"
#
# or
#
# # multiple results:
# ./script/run_in_env.sh ./script/query_config.pl "//database[1]/db" | xargs createdb
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use Data::Dumper;
use XML::Simple qw(:strict);
use XML::LibXML;

# Generates XML from the hashref such as:
#
# <?xml version='1.0' standalone='yes'?>
# <mediawords>
#   <Plugin_Authentication>
#     <default_realm>users</default_realm>
#     <users>
#       <credential>
#         <class>MediaWords</class>
#       </credential>
#       <store>
#         <class>MediaWords</class>
#       </store>
#     </users>
#   </Plugin_Authentication>
#   <database>
#     <db>mediacloud</db>
#     <host>localhost</host>
#     <label>LABEL</label>
#     <pass>mediacloud</pass>
#     <type>pg</type>
#     <user>mediaclouduser</user>
#   </database>
#   <database>
#     <db>mediacloud_test</db>
#     <host>localhost</host>
#     <label>test</label>
#     <pass>mediacloud</pass>
#     <type>pg</type>
#     <user>mediaclouduser</user>
#   </database>
#   <!-- ... -->
#   <mediawords>
#     <always_show_stack_traces>no</always_show_stack_traces>
#     <!-- ... -->
#   </mediawords>
#   <name>MediaWords</name>
#   <session>
#     <storage>/Users/pypt/tmp/mediacloud-session</storage>
#   </session>
# </mediawords>
sub _hashref_to_xml($)
{
    my $hashref = shift;

    my $xs = XML::Simple->new( KeyAttr => [], NoAttr => 1, RootName => 'mediawords', XMLDecl => 1 );
    my $xml = $xs->XMLout( $hashref );

    unless ( $xml )
    {
        return undef;
    }

    # (Naively) rename elements such as "<Plugin::Authentication>"
    $xml =~ s/<(\/?[\w\d]+?)::([\w\d]+?)>/<$1_$2>/gsi;

    return $xml;
}

# Match XPath query against XML
# Returns: an arrayref (if elements were matched), or
# undef (if nothing was matched or if a parser error occurred)
sub _match_xpath($$)
{
    my ( $xml, $xpath ) = @_;

    my $xml_data = XML::LibXML->load_xml( string => $xml );
    unless ( $xml_data )
    {
        ERROR "Unable to parse XML: $xml_data";
        return undef;
    }

    my $nodes = $xml_data->findnodes( $xpath );
    if ( $nodes->size() == 0 )
    {
        return undef;
    }

    my $results = [];
    foreach my $node ( $nodes->get_nodelist )
    {
        my $content = $node->textContent . '';
        push( @{ $results }, $content );
    }

    return $results;
}

sub for_every_hash_value
{
    my ( $hash, $fn ) = @_;

    my $new_hash = {};
    while ( my ( $key, $value ) = each %{ $hash } )
    {
        if ( ref $value eq ref {} )
        {
            $new_hash->{ $key } = for_every_hash_value( $value, $fn );
        }
        else
        {
            $new_hash->{ $key } = $fn->( $key, $value );
        }
    }

    return $new_hash;
}

sub main
{
    my $usage = "Usage: $0 xpath_query\n";

    if ( scalar @ARGV != 1 )
    {
        die $usage;
    }

    my $query = $ARGV[ 0 ];

    my $config = MediaWords::Util::Config::get_config();

    TRACE Dumper( $config );

    $config = for_every_hash_value(
        $config,
        sub {
            my ( $key, $value ) = @_;

            if ( ref $value and ref $value ne ref [] and ref $value ne ref {} )
            {
                # Convert unknown objects into scalars
                $value = $value . '';
            }
            return $value;
        }
    );

    # Convert the configuration hash to an XML object so that we can use XPath
    # queries against it
    my $xml = _hashref_to_xml( $config );
    unless ( $xml )
    {
        die "Unable to convert the configuration to XML.\n";
    }

    TRACE $xml;

    # Match XPath
    my $results = _match_xpath( $xml, $query );
    unless ( $results )
    {
        die "Unable to match the XPath query '$query' against XML:\n$xml\n";
    }

    foreach my $result ( @{ $results } )
    {
        print "$result\n";
    }
}

main();
