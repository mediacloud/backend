package MediaWords::Util::ExtractorFactory;
use Modern::Perl "2012";
use MediaWords::CommonLibs;
use MediaWords::Util::Config;
use MediaWords::Util::HeuristicExtractor;
use MediaWords::Util::CrfExtractor;

use strict;

sub createExtractor
{
    my $config = MediaWords::Util::Config::get_config;

    my $extractor_method = $config->{ mediawords }->{ extractor_method };

    die unless defined( $extractor_method );

    my $ret;
    given ( $extractor_method )
    {
        when ( 'HeuristicExtractor' ) { $ret = MediaWords::Util::HeuristicExtractor->new(); }
        when ( 'CrfExtractor' )       { $ret = MediaWords::Util::CrfExtractor->new(); }
        default { die 'Invalid extractor methods: $extractor_method'; }
    }

    die unless defined( $ret );

    return $ret;
}

1;
