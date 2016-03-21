package MediaWords::Util::Translate;
use Modern::Perl "2015";
use MediaWords::CommonLibs;

# various functions for manipulating html

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(translate);

# various functions for editing feed and medium tags

use strict;
use WebService::Google::Language;

use Text::Trim;
eval { use CHI; };

die "$@" if $@;

use MediaWords::Util::Config;

my $mediacloud_data_dir = MediaWords::Util::Config::get_config->{ mediawords }->{ data_dir };

my $cache = CHI->new(
    driver           => 'File',
    expires_in       => '1 week',
    expires_variance => '0.1',
    root_dir         => "${ mediacloud_data_dir }/cache/translate",
    cache_size       => '3m'
);

sub _translate
{
    my $original_text = shift;

    #say STDERR "starting translate";

    my $service = WebService::Google::Language->new(
        'referer' => 'http://example.com/',

        #        'src'     => 'ru',
        'dest' => 'en',
    );

    my $text = $original_text;

    trim( $text );

    return $original_text unless $text;

    #say STDERR "sending request for '$text'";
    $text = substr( $text, 0, 500 );

    #detect the language of source text
    #TODO is this detect() call necessary? - DRL 20 aug 2010
    $service->detect( $text );
    my $result = $service->translate( $text );

    #say STDERR "got result";

    if ( $result->error )
    {

        #say STDERR $result->message;
        #say STDERR 'error translating';
        return $text;
    }
    else
    {

        #say STDERR 'no error translating';
        #say STDERR $result->translation;
        return $result->translation;
    }
}

sub translate
{
    my $text = shift;

    my $ret = $cache->get( $text );
    if ( !defined( $ret ) )
    {

        #say STDERR "Translation for '$text' not in cache";
        $ret = _translate( $text );
        $cache->set( $text, $ret );
    }
    else
    {

        #say STDERR "Translation for '$text' in cache";
    }

    return $ret;
}

1;
