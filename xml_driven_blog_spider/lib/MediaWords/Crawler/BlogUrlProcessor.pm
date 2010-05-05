package MediaWords::Crawler::BlogUrlProcessor;

use strict;

# MODULES

use Data::Dumper;
use DateTime;
use Encode;
use Feed::Find;
use HTML::Strip;
use HTML::LinkExtractor;
use IO::Compress::Gzip;
use URI::Split;
use XML::Feed;
use Carp;
use Switch;

use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Feeds;
use MediaWords::Util::Config;
use FindBin;

my $_xml_driver_file_location = "$FindBin::Bin/../spider_config.xml";

# METHODS

sub get_base_site_from_url
{
    my ($url) = @_;

    print "get_base_site_from_url: url = '$url'\n";
    my $host = lc( ( URI::Split::uri_split($url) )[1] );

    ##strip out sub domains

    $host =~ s/.*\.([^.]+\.[^.]+)/\1/;

    print "get_base_site_from_url: host='$host'\n";
    return $host;
}

sub get_base_site_rules
{
    my ($url) = @_;

    my $base_site = get_base_site_from_url($url);
    my $parser    = XML::LibXML->new;

    my $doc = $parser->parse_file($_xml_driver_file_location);

    #print Dumper($doc);

    #print '//site[@base_domain="' . $base_site . '"]' . "\n";

    my $nodes = $doc->findnodes( '//site[@base_domain="' . $base_site . '"]' );

    #print Dumper($nodes);

    #print "list size " . $nodes->size() . "\n";

    my @node_list = $nodes->get_nodelist();

    #print Dumper(@node_list);

    return $node_list[0];
}

sub is_spidered_host
{
    my ($url) = @_;

    if ( get_base_site_rules($url) )
    {
        print "XXX '$url' is spidered host\n";
    }
    else
    {
        print "XXX '$url' is nonspidered host\n";
    }
}

sub is_blog_home_page_url
{
    my ($url) = @_;

    my $base_site_rules = get_base_site_rules($url);

    return 0 if ( !$base_site_rules );

    my $blog_url_validation_element = ( $base_site_rules->getChildrenByTagName('blog_url_validation')->get_nodelist() )[0];

    return 0 if ( !$blog_url_validation_element );

    my @blog_url_validation_rules = $blog_url_validation_element->getChildrenByTagName('*');

    #print Dumper(@url_conversion_rules);

    for my $url_validation_rule (@blog_url_validation_rules)
    {
        print "validation url using\n";
        print Dumper ( $url_validation_rule->toString );

        return 0 if ( !_url_passes_validation_rule( $url_validation_rule, $url ) );

        print "passed validation\n";
    }

    print "passed all validation\n";
    return 1;
}

sub _url_passes_validation_rule
{
    my ( $url_validation_rule, $url ) = @_;

    switch ( $url_validation_rule->nodeName )
    {
        case 'require_string_starts_with'
        {
            my $ind = index( $url, $url_validation_rule->textContent() );
            return ( $ind == 0 );
        }
        case 'require_string'
        {
            my $ind = index( $url, $url_validation_rule->textContent() );
            return ( $ind != -1 );
        }
        case 'forbid_string'
        {
            print "XXX index($url, " . "$url_validation_rule->textContent" . "())\n";
            my $ind = index( $url, $url_validation_rule->textContent() );
            return ( $ind == -1 );
        }
        else
        {
            die "Invalid validation rule : " . $url_validation_rule->nodeName . " ";
        }
    }
}

sub canonicalize_url
{
    my ($url) = @_;

    print "string canonicalize_url\n";

    my $ret             = $url;
    my $base_site_rules = get_base_site_rules($url);

    return $ret if ( !$base_site_rules );

    my $url_conversion_rule_element =
      ( $base_site_rules->getChildrenByTagName('url_to_blog_home_conversion')->get_nodelist() )[0];

    #print $url_conversion_rule_element->toString() . "\n";

    my @url_conversion_rules = $url_conversion_rule_element->getChildrenByTagName('*');

    #print Dumper(@url_conversion_rules);

    for my $conversion_rule (@url_conversion_rules)
    {
        print Dumper ( $conversion_rule->toString );

        switch ( $conversion_rule->nodeName )
        {
            case 'get_tilda_directory_root' { $ret = canonicalize_tilda_url($ret); }
            case 'get_domain_only_url'      { $ret = get_domain_only_url($ret); }
            case 'get_child_directory'      { $ret = get_child_directory( $ret, $conversion_rule ); }
            case 'change_subdomain'         { $ret = change_subdomain( $ret, $conversion_rule ); }
            case 'regular_expression_replace_url_path'
            {
                $ret = regular_expression_replace_in_path( $ret, $conversion_rule );
            }
            else { die "Invalid url conversion rule: " . $conversion_rule->nodeName; }

        }
    }
    print "returning: '$ret'\n";

    return $ret;
}

sub regular_expression_replace_in_path
{
    my ( $url, $conversion_rule ) = @_;
    print "Before '$url'\n";

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split($url);

    my $find_regex_element    = ( $conversion_rule->getChildrenByTagName('find_expression')->get_nodelist() )[0];
    my $replace_regex_element = ( $conversion_rule->getChildrenByTagName('replace_expression')->get_nodelist() )[0];

    die unless ( $find_regex_element && $replace_regex_element );

    my $find_regex    = $find_regex_element->textContent() . '';
    my $replace_regex = $replace_regex_element->textContent() . '';

    print "s/'$find_regex'/'$replace_regex'/;\n";
    eval("\$path =~ s/$find_regex/$replace_regex/;");

    $url = URI::Split::uri_join( $scheme, $auth, $path );
    print "After '$url'\n";

    return $url;
}

sub change_subdomain
{
    my ( $url, $conversion_rule ) = @_;

    print "Before '$url'\n";

    my $new_sub_domain = $conversion_rule->getAttribute("new_subdomain");

    die if ( !$new_sub_domain );

    my $base_site = get_base_site_from_url($url);

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split($url);

    $auth = "$new_sub_domain.$base_site";

    $url = URI::Split::uri_join( $scheme, $auth, $path );
    print "After '$url'\n";

    return $url;
}

sub get_child_directory
{

    my ( $url, $conversion_rule ) = @_;

    print "Before '$url'\n";

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split($url);

    my $parent_directory = $conversion_rule->getAttribute("parent_directory");

    die if ( !$parent_directory );

    return $url if ( index( $path, $parent_directory ) != 0 );

    my $path_part_to_update = \substr( $path, length($parent_directory) );

    $$path_part_to_update =~ s/\/([^\/?]*).*/\/\1/;

    #print "path is $path\n";

    $url = URI::Split::uri_join( $scheme, $auth, $path );
    print "After '$url'\n";

    return $url;
}

sub get_domain_only_url
{
    my ($url) = @_;
    print "Before '$url'\n";

    $url = lc( URI::Split::uri_join( ( URI::Split::uri_split($url) )[ 0 .. 1 ] ) );
    print "After '$url'\n";
    return $url;
}

sub canonicalize_tilda_url
{
    my ($url) = @_;
    print "Before '$url'\n";

    $url =~ s/~([^\/?]*).*/~\1/;
    print "After '$url'\n";

    return $url;
}

1;
