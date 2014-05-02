package MediaWords::Crawler::BlogUrlCanonicalizer;
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

use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;
use MediaWords::Crawler::BlogUrlProcessor;

# METHODS

sub get_canonical_blog_url
{
    my ( $uri ) = @_;

    #print "get_canonical_blog_url '$uri'\n";

    #my $rules = MediaWords::Crawler::BlogUrlProcessor::get_base_site_rules($uri);

    #print Dumper($rules);
    my $ret = MediaWords::Crawler::BlogUrlProcessor::canonicalize_url( $uri );

    #print "get_canonical_blog_url returning:'$ret'\n";

    return $ret;
}

1;
