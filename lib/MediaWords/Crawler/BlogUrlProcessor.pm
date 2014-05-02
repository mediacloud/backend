package MediaWords::Crawler::BlogUrlProcessor;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

use strict;
use warnings;

# MODULES

use Data::Dumper;
use DateTime;
use Encode;
use Feed::Find;
use HTML::LinkExtractor;
use URI::Split;
use Carp;
use if $] < 5.014, Switch => 'Perl6';
use if $] >= 5.014, feature => 'switch';

#use feature 'switch';

use XML::LibXML;

use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;
use FindBin;

my $_xml_driver_file_location = "$FindBin::Bin/../spider_config.xml";

# METHODS

my $_verbose_logs = 0;

sub _log
{
    my @args = @_;

    if ( $_verbose_logs )
    {
        print @args;
    }
    return;
}

sub get_base_site_from_url
{
    my ( $url ) = @_;

    _log "get_base_site_from_url: url = '$url'\n";
    my $host = lc( ( URI::Split::uri_split( $url ) )[ 1 ] );

    ##strip out sub domains

    $host =~ s/.*\.([^.]+\.[^.]+)/$1/;

    _log "get_base_site_from_url: host='$host'\n";
    return $host;
}

my $base_site_rules_cache = {};

sub get_base_site_rules
{
    my ( $url ) = @_;

    my $base_site = get_base_site_from_url( $url );

    if ( exists( $base_site_rules_cache->{ $base_site } ) )
    {
        return $base_site_rules_cache->{ $base_site };
    }

    print "Looking up base site rules for '$base_site'\n";

    my $parser = XML::LibXML->new;

    my $doc = $parser->parse_file( $_xml_driver_file_location );

    #print Dumper($doc);

    #print '//site[@base_domain="' . $base_site . '"]' . "\n";

    my $nodes = $doc->findnodes( '//site[@base_domain="' . $base_site . '"]' );

    #print Dumper($nodes);

    #print "list size " . $nodes->size() . "\n";

    my @node_list = $nodes->get_nodelist();

    #print Dumper(@node_list);

    $base_site_rules_cache->{ $base_site } = $node_list[ 0 ];

    return $base_site_rules_cache->{ $base_site };
}

sub is_spidered_host
{
    my ( $url ) = @_;

    if ( get_base_site_rules( $url ) )
    {
        _log "XXX '$url' is spidered host\n";
        return 1;
    }
    else
    {
        _log "XXX '$url' is nonspidered host\n";
        return 0;
    }
}

sub get_rss_detection_method
{
    my ( $url ) = @_;
    my $base_site_rules = get_base_site_rules( $url );

    return 0 if ( !$base_site_rules );

    my $rss_detection_method_element =
      ( $base_site_rules->getChildrenByTagName( 'rss_detection_method' )->get_nodelist() )[ 0 ];

    return 0 if ( !$rss_detection_method_element );

    return $rss_detection_method_element->getAttribute( "type" );
}

sub get_friends_list
{
    my ( $url ) = @_;
    my $base_site_rules = get_base_site_rules( $url );

    #print "NO base site rules\n"   if ( !$base_site_rules );
    return if ( !$base_site_rules );

    my $blog_url_to_friends_list_page_element =
      ( $base_site_rules->getChildrenByTagName( 'blog_url_to_friends_list_page' )->get_nodelist() )[ 0 ];

    #print "NO friends list element\n"  if ( !$blog_url_to_friends_list_page_element );
    return if ( !$blog_url_to_friends_list_page_element );

    my $ret = canonicalize_url_impl( $url, $blog_url_to_friends_list_page_element );

    #print STDERR "Friendslist page: '$url' -> '$ret'\n";
    return $ret;
}

sub test_url
{
    my ( $url, $url_tests_element ) = @_;

    my @blog_url_validation_rules = $url_tests_element->getChildrenByTagName( '*' );

    #_log Dumper(@url_conversion_rules);

    for my $url_validation_rule ( @blog_url_validation_rules )
    {
        _log "validation url using\n";
        _log Dumper( $url_validation_rule->toString );

        return 0 if ( !_url_passes_validation_rule( $url_validation_rule, $url ) );

        _log "passed validation\n";
    }

    _log "passed all validation\n";
    return 1;
}

sub is_blog_home_page_url_impl
{
    my ( $url ) = @_;

    my $base_site_rules = get_base_site_rules( $url );

    return 0 if ( !$base_site_rules );

    my $blog_url_validation_element =
      ( $base_site_rules->getChildrenByTagName( 'blog_url_validation' )->get_nodelist() )[ 0 ];

    return 0 if ( !$blog_url_validation_element );

    return test_url( $url, $blog_url_validation_element );
}

sub is_blog_home_page_url
{
    my ( $url ) = @_;

    my $ret = is_blog_home_page_url_impl( $url );

    if ( $ret )
    {
        _log " is_blog_home_page_url: '$url' is blog home page\n";
    }
    else
    {
        _log " is_blog_home_page_url: '$url' is not blog home page\n";
    }

    return $ret;
}

sub _url_passes_validation_rule
{
    my ( $url_validation_rule, $url ) = @_;

    my $nodeName = $url_validation_rule->nodeName;

    if ( $nodeName eq 'require_string_starts_with' )
    {
        my $ind = index( $url, $url_validation_rule->textContent() );
        return ( $ind == 0 );

    }
    elsif ( $nodeName eq 'require_string' )
    {
        my $ind = index( $url, $url_validation_rule->textContent() );
        return ( $ind != -1 );

    }
    elsif ( $nodeName eq 'forbid_string' )
    {
        my $ind = index( $url, $url_validation_rule->textContent() );
        return ( $ind == -1 );

    }
    else
    {
        die "Invalid validation rule : " . $url_validation_rule->nodeName . " ";

    }
}

sub canonicalize_url_impl
{
    my ( $url, $url_conversion_rule_element ) = @_;

    #_log $url_conversion_rule_element->toString() . "\n";

    my @url_conversion_rules = $url_conversion_rule_element->getChildrenByTagName( '*' );

    #_log Dumper(@url_conversion_rules);

    my $ret = $url;

    for my $conversion_rule ( @url_conversion_rules )
    {
        _log Dumper( $conversion_rule->toString );

        my $nodeName = $conversion_rule->nodeName;

        if ( $nodeName eq 'append_directory' )
        {
            $ret = append_directory( $ret, $conversion_rule );

        }
        elsif ( $nodeName eq 'get_tilda_directory_root' )
        {
            $ret = canonicalize_tilda_url( $ret );

        }
        elsif ( $nodeName eq 'get_domain_only_url' )
        {
            $ret = get_domain_only_url( $ret );

        }
        elsif ( $nodeName eq 'get_base_directory' )
        {
            $ret = get_base_directory( $ret, $conversion_rule );

        }
        elsif ( $nodeName eq 'get_child_directory' )
        {
            $ret = get_child_directory( $ret, $conversion_rule );

        }
        elsif ( $nodeName eq 'change_subdomain' )
        {
            $ret = change_subdomain( $ret, $conversion_rule );

        }
        elsif ( $nodeName eq 'regular_expression_replace_url_query' )
        {
            $ret = regular_expression_replace_in_query( $ret, $conversion_rule );

        }
        elsif ( $nodeName eq 'regular_expression_replace_url_path' )
        {
            $ret = regular_expression_replace_in_path( $ret, $conversion_rule );

        }
        elsif ( $nodeName eq 'regular_expression_replace_url_path_and_query' )
        {
            $ret = regular_expression_replace_in_path_and_query( $ret, $conversion_rule );

        }
        elsif ( $nodeName eq 'set_path' )
        {
            $ret = set_path( $ret, $conversion_rule );

        }
        elsif ( $nodeName eq 'set_query' )
        {
            $ret = set_query( $ret, $conversion_rule );

        }
        else
        {
            die "Invalid url conversion rule: " . $nodeName;

        }
    }

    _log "returning: '$ret'\n";

    return $ret;
}

sub canonicalize_url
{
    my ( $url ) = @_;

    _log "string canonicalize_url\n";

    my $ret             = $url;
    my $base_site_rules = get_base_site_rules( $url );

    return $ret if ( !$base_site_rules );

    my $url_conversion_rule_element =
      ( $base_site_rules->getChildrenByTagName( 'url_to_blog_home_conversion' )->get_nodelist() )[ 0 ];

    #The standard case of only 1 conversion rule list.
    if ( $url_conversion_rule_element )
    {
        return canonicalize_url_impl( $url, $url_conversion_rule_element );
    }
    else
    {
        my $multiple_url_conversion_rule_element =
          ( $base_site_rules->getChildrenByTagName( 'multiple_url_to_blog_home_conversion' )->get_nodelist() )[ 0 ];

        my @cases = $multiple_url_conversion_rule_element->getChildrenByTagName( '*' );

        for my $case ( @cases )
        {
            if ( ( $case->nodeName ne 'default' ) )
            {
                my $url_tests = ( $case->getChildrenByTagName( 'url_tests' )->get_nodelist() )[ 0 ];

                next unless test_url( $url, $url_tests );
            }
            $url_conversion_rule_element =
              ( $case->getChildrenByTagName( 'url_to_blog_home_conversion' )->get_nodelist() )[ 0 ];

            $ret = canonicalize_url_impl( $url, $url_conversion_rule_element );
            _log "multiple url site url: '$url' is canonicalized to $ret\n";
            return $ret;
        }
    }

    die "Invalid XML: (url = '$url') rules = " . $base_site_rules->toString;
}

sub regex_replace_impl
{
    my ( $string, $conversion_rule ) = @_;

    my $find_regex_element    = ( $conversion_rule->getChildrenByTagName( 'find_expression' )->get_nodelist() )[ 0 ];
    my $replace_regex_element = ( $conversion_rule->getChildrenByTagName( 'replace_expression' )->get_nodelist() )[ 0 ];

    die unless ( $find_regex_element && $replace_regex_element );

    my $find_regex    = $find_regex_element->textContent() . '';
    my $replace_regex = $replace_regex_element->textContent() . '';

    _log "Before string '$string'\n";
    _log "s/'$find_regex'/'$replace_regex'/;\n";
    eval( "\$string =~ s/$find_regex/$replace_regex/;" );
    _log "After string '$string'\n";

    return $string;
}

sub regular_expression_replace_in_query
{
    my ( $url, $conversion_rule ) = @_;
    _log "Before '$url'\n";

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split( $url );

    $query = regex_replace_impl( $query, $conversion_rule );

    $url = URI::Split::uri_join( $scheme, $auth, $path, $query );
    _log "After '$url'\n";

    return $url;
}

sub regular_expression_replace_in_path_and_query
{
    my ( $url, $conversion_rule ) = @_;
    _log "Before '$url'\n";

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split( $url );

    my $path_and_query = "$path?$query";
    $path_and_query = regex_replace_impl( $path_and_query, $conversion_rule );

    ( $path, $query ) = split( /\?/, $path_and_query );
    $url = URI::Split::uri_join( $scheme, $auth, $path, $query );
    _log "After '$url'\n";

    return $url;
}

sub regular_expression_replace_in_path
{
    my ( $url, $conversion_rule ) = @_;
    _log "Before '$url'\n";

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split( $url );

    $path = regex_replace_impl( $path, $conversion_rule );

    if ( $conversion_rule->getAttribute( "perserve_query" ) )
    {

        #_log Dumper ($scheme, $auth, $path, $query );
        $url = URI::Split::uri_join( $scheme, $auth, $path, $query );
    }
    else
    {
        $url = URI::Split::uri_join( $scheme, $auth, $path );
    }

    _log "After '$url'\n";

    return $url;
}

sub set_path
{
    my ( $url, $conversion_rule ) = @_;
    _log "Before '$url'\n";

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split( $url );

    $path = $conversion_rule->getAttribute( "path" );

    die unless $path;

    $url = URI::Split::uri_join( $scheme, $auth, $path, $query );

    _log "After '$url'\n";

    return $url;
}

sub set_query
{
    my ( $url, $conversion_rule ) = @_;
    _log "Before '$url'\n";

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split( $url );

    $query = $conversion_rule->getAttribute( "query" );

    die unless $query;

    $url = URI::Split::uri_join( $scheme, $auth, $path, $query );

    _log "After '$url'\n";

    return $url;
}

sub append_directory
{
    my ( $url, $conversion_rule ) = @_;
    _log "Before '$url'\n";

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split( $url );

    my $directory = $conversion_rule->getAttribute( "directory" );

    die unless $directory;

    #delete / at the end of the string
    $path =~ s/\/$//;

    $path = "$path/$directory/";

    if ( $conversion_rule->getAttribute( "perserve_query" ) )
    {

        #_log Dumper ($scheme, $auth, $path, $query );
        $url = URI::Split::uri_join( $scheme, $auth, $path, $query );
    }
    else
    {
        $url = URI::Split::uri_join( $scheme, $auth, $path );
    }

    _log "After '$url'\n";

    return $url;
}

sub change_subdomain
{
    my ( $url, $conversion_rule ) = @_;

    _log "Before '$url'\n";

    my $new_sub_domain = $conversion_rule->getAttribute( "new_subdomain" );

    die if ( !$new_sub_domain );

    my $base_site = get_base_site_from_url( $url );

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split( $url );

    $auth = "$new_sub_domain.$base_site";

    $url = URI::Split::uri_join( $scheme, $auth, $path );
    _log "After '$url'\n";

    return $url;
}

sub get_base_directory
{

    my ( $url, $conversion_rule ) = @_;

    _log "Before '$url'\n";

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split( $url );

    $path =~ s/^(\/[^\/]+\/).*/$1/;

    $url = URI::Split::uri_join( $scheme, $auth, $path );
    _log "After '$url'\n";

    return $url;
}

sub get_child_directory
{

    my ( $url, $conversion_rule ) = @_;

    _log "Before '$url'\n";

    my ( $scheme, $auth, $path, $query, $frag ) = URI::Split::uri_split( $url );

    my $parent_directory = $conversion_rule->getAttribute( "parent_directory" );

    die if ( !$parent_directory );

    return $url if ( index( $path, $parent_directory ) != 0 );

    my $path_part_to_update = \substr( $path, length( $parent_directory ) );

    $$path_part_to_update =~ s/\/([^\/?]*).*/\/$1/;

    #_log "path is $path\n";

    $url = URI::Split::uri_join( $scheme, $auth, $path );
    _log "After '$url'\n";

    return $url;
}

sub get_domain_only_url
{
    my ( $url ) = @_;
    _log "Before '$url'\n";

    $url = lc( URI::Split::uri_join( ( URI::Split::uri_split( $url ) )[ 0 .. 1 ] ) );
    _log "After '$url'\n";
    return $url;
}

sub canonicalize_tilda_url
{
    my ( $url ) = @_;
    _log "Before '$url'\n";

    $url =~ s/~([^\/?]*).*/~$1/;
    _log "After '$url'\n";

    return $url;
}

1;
