use strict;
use warnings;

use Test::More tests => 19;
use Test::NoWarnings;
use Test::Deep;

use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;
use MediaWords::Test::DB;
use Readonly;

# Integer constants (in case Date::Parse::str2time fails)
Readonly my $TIMESTAMP_12_00_GMT => 1326801600;    # Tue, 17 Jan 2012 12:00:00 GMT (UTC); for dates without time / timezone
Readonly my $TIMESTAMP_12_00_EST => 1326819600;    # Tue, 17 Jan 2012 12:00:00 EST (-05:00)

BEGIN { use_ok 'MediaWords::TM::GuessDate' }
BEGIN { use_ok 'MediaWords::Util::Web' }
BEGIN { use_ok 'MediaWords::TM::GuessDate::Result' }
BEGIN { use_ok 'Date::Parse' }

# Returns URL dating result
sub _gr($;$)
{
    my ( $html, $story_url ) = @_;
    $story_url ||= 'http://www.example.com/story.html';

    return MediaWords::TM::GuessDate::guess_date( $story_url, $html );
}

# Returns timestamp of the page or undef
sub _gt($;$)
{
    my ( $html, $story_url ) = @_;

    my $result = _gr( $html, $story_url );
    if ( $result->{ result } eq $MediaWords::TM::GuessDate::Result::FOUND )
    {
        return $result->{ timestamp };
    }
    else
    {
        return undef;
    }
}

# Returns dating result of the page; also fetches the URL
sub _gr_url($)
{
    my ( $story_url ) = @_;

    my $html = '';
    unless ( $story_url =~ /example\.(com|net|org)$/gi )
    {

        # 404 Not Found pages will be empty
        my $ua = MediaWords::Util::Web::UserAgent->new();
        $html = $ua->get_string( $story_url ) || '';
    }

    return _gr( $html, $story_url );
}

# Shortcut for making UNIX timestamps out of RFC 822 dates
sub _ts($)
{
    my $date = shift;
    return Date::Parse::str2time( $date );
}

sub test_dates()
{
    is( _gt( '<meta property="article:published_time" content="2012-01-17T12:00:00-05:00" />' ),
        $TIMESTAMP_12_00_EST, 'guess_by_og_article_published_time' );

    is( _gt( '<meta name="pubdate" content="2012-01-17 12:00:00" />' ), $TIMESTAMP_12_00_GMT, 'guess_by_meta_pubdate' );

    # LiveJournal
    is( _gt( '<abbr class="published" title="2012-01-17T12:00:00-05:00">' ),
        $TIMESTAMP_12_00_EST, '_guess_by_abbr_published_updated_date' );

}

sub test_not_found()
{
    is(
        _gr_url( 'http://www.calchannel.com/proposition-36-three-strikes-law/' )->{ result },
        $MediaWords::TM::GuessDate::Result::NOT_FOUND,
        '404 Not Found'
    );
    is( _gr_url( 'http://www.15min.lt/////' )->{ result }, $MediaWords::TM::GuessDate::Result::NOT_FOUND, 'no path in URL' );
    is(
        _gr_url( 'http://en.wikipedia.org/wiki/1980s_in_fashion' )->{ result },
        $MediaWords::TM::GuessDate::Result::NOT_FOUND,
        'Wikipedia URL'
    );
    is(
        _gr_url( 'https://www.phpbb.com/community/viewforum.php?f=14' )->{ result },
        $MediaWords::TM::GuessDate::Result::NOT_FOUND,
        'phpBB forum'
    );
    is(
        _gr_url( 'https://twitter.com/ladygaga' )->{ result },
        $MediaWords::TM::GuessDate::Result::NOT_FOUND,
        'Twitter user URL'
    );
    is(
        _gr_url(
'https://www.facebook.com/notes/facebook-engineering/adding-face-to-every-ip-celebrating-ipv6s-one-year-anniversary/10151492544578920'
          )->{ result },
        $MediaWords::TM::GuessDate::Result::NOT_FOUND,
        'Facebook URL'
    );
    is(
        _gr_url( 'http://vimeo.com/blog/archive/year:2013' )->{ result },
        $MediaWords::TM::GuessDate::Result::NOT_FOUND,
        'looks like URL of archive'
    );
    is(
        _gr_url( 'http://www.timesunion.com/news/crime/article/3-strikes-law-reformed-fewer-harsh-sentences-4013514.php' )
          ->{ result },
        $MediaWords::TM::GuessDate::Result::NOT_FOUND,
        'timesunion.com HTTP 404 Not Found'
    );
    is(
        _gr_url( 'http://www.seattlepi.com/news/crime/article/ACLU-challenges-human-trafficking-initiative-4018819.php' )
          ->{ result },
        $MediaWords::TM::GuessDate::Result::NOT_FOUND,
        'seattlepi.com HTTP 404 Not Found'
    );
    is(
        _gr_url( 'http://www.kgoam810.com/Article.asp?id=2569360&spid=' )->{ result },
        $MediaWords::TM::GuessDate::Result::NOT_FOUND,
        'kgoam810.com HTTP access denied'
    );
}

sub main
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_dates();
    test_not_found();

    Test::NoWarnings::had_no_warnings();
}

main();
