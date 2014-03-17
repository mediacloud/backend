package MediaWords::Crawler::BlogSpiderPostingHandler;
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
use List::MoreUtils qw (any uniq);
use URI::Split;
use Carp;

use MediaWords::Crawler::Pager;
use MediaWords::DBI::Downloads;
use MediaWords::Util::Config;
use MediaWords::Crawler::BlogPageProcessor;
use MediaWords::Crawler::BlogUrlCanonicalizer;
use MediaWords::Crawler::BlogUrlProcessor;
use MediaWords::Crawler::BlogSpiderDbUtils;

# METHODS

sub new
{
    my ( $class, $engine ) = @_;

    my $self = {};
    bless( $self, $class );

    $self->engine( $engine );
    $self->{ non_spidered_uris }           = {};
    $self->{ non_spidered_urls }           = {};
    $self->{ already_processed_url_count } = 0;
    $self->{ not_yet_processed_url_count } = 0;
    return $self;
}

sub process_spidered_posting_download
{
    my ( $self, $download, $response ) = @_;

    my $url = $response->request->uri;

    print "processing blog post '$url'\n";
    $self->_process_links( $download, $response );

    return;
}

sub _url_already_spidered
{
    my ( $self, $url ) = @_;

    my $dbs = $self->engine->dbs;

    my $downloads = $dbs->query(
"select * from downloads where (type = 'spider_blog_home' or type = 'spider_posting' or type = 'spider_rss' or type = 'spider_blog_friends_list') and url = ? limit 1",
        $url
    )->hashes;

    if ( scalar( @$downloads ) )
    {

        #print "Link '$url' already in downloads table not re-adding\n";
        return 1;
    }
    else
    {

        #print "Link '$url' not in downloads table\n";
        return 0;
    }
}

sub _url_already_processed
{
    my ( $self, $url ) = @_;

    my $dbs = $self->engine->dbs;

    my $rejected_blogs = $dbs->query( "select * from rejected_blogs where url = ? limit 1", $url )->hashes;

    if ( scalar( @$rejected_blogs ) )
    {
        return 1;
    }

    my $found_blogs = $dbs->query( "select * from found_blogs where url = ? limit 1", $url )->hashes;

    if ( scalar( @$found_blogs ) )
    {
        return 1;
    }

    if ( MediaWords::Crawler::BlogSpiderDbUtils::url_in_downloads( $dbs, $url ) )
    {
        return 1;
    }

    return 0;
}

sub list_contains
{
    ( my $value, my $list ) = @_;

    return any { $_ eq $value } @{ $list };
}

sub _is_url_non_spidered_host
{
    my ( $url ) = @_;

    return !MediaWords::Crawler::BlogUrlProcessor::is_spidered_host( $url );
}

sub _is_url_black_listed_for_spider
{
    my ( $url ) = @_;

    my $ret = !MediaWords::Crawler::BlogUrlProcessor::is_blog_home_page_url( $url );

    if ( $ret )
    {

        #print "XXX Blacklisted url: $url\n";
    }
    else
    {

        #print "XXX Not blacklisted url: $url\n";
    }

    return $ret;
}

sub _uri_should_be_spidered
{
    my ( $self, $uri ) = @_;
    if ( defined( $self->{ non_spidered_uris }->{ $uri . '' } ) )
    {

        #print "_uri_should_be_spidered returning false for uri '$uri'\n";
        return 0;
    }

    my $url = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url( $uri );

    if ( defined( $self->{ non_spidered_urls }->{ $url } ) )
    {

        #print "_uri_should_be_spidered returning false for url '$url'\n ";
        return 0;
    }

    my $ret = $self->_url_should_be_spidered_impl( $url );

    if ( !$ret )
    {

        #print "_uri_should_be_spidered updating black list with uri: '$uri' and 'url: '$url'\n";
        $self->{ non_spidered_uris }->{ $uri . '' } = 1;
        $self->{ non_spidered_urls }->{ $url } = 1;
    }

    return $ret;
}

sub _url_should_be_spidered_impl
{
    my ( $self, $url ) = @_;

    return 0 if ( _is_url_black_listed_for_spider( $url ) );

    if ( $self->_url_already_processed( $url ) || $self->_url_already_spidered( $url ) )
    {
        print STDERR "Already processed $url\n";
        $self->{ already_processed_url_count }++;
        return 0;
    }
    else
    {
        print STDERR "Not yet processed $url\n";
        $self->{ not_yet_processed_url_count }++;
        return 1;
    }

    die "unreachable";
}

sub _add_spider_download
{
    my ( $self, $download, $uri ) = @_;

    my $url = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url( $uri );

    my $dbs = $self->engine->dbs;

    print "Adding spider blog home download for $url\n";

    $dbs->create(
        'downloads',
        {
            url    => $url,
            parent => $download->{ downloads_id },
            host   => lc( ( URI::Split::uri_split( $url ) )[ 1 ] ),

            #                stories_id    => 1,
            type          => 'spider_blog_home',
            sequence      => 0,
            state         => 'pending',
            priority      => 0,
            download_time => 'now()',
            extracted     => 'f'
        }
    );

    die unless $self->_url_already_processed( $url );

    #$dbs->commit;
}

#TODO refactor this sub exists in multiple places
sub _get_site_from_url
{
    my ( $url ) = @_;

    my $host = lc( ( URI::Split::uri_split( $url ) )[ 1 ] );

    ##strip out sub domains

    $host =~ s/.*\.([^.]*\.[^.]*)/$1/;

    return $host;
}

my $_non_host_link_count = 0;

sub _log_link_to_non_spidered_host
{
    my ( $self, $uri ) = @_;

    my $url = MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url( $uri );

    my $host = lc( ( URI::Split::uri_split( $url ) )[ 1 ] );

    my $dbs = $self->engine->dbs;

    print "Logging non spidered_host link for '$host' from '$url'\n";

    if ( !$dbs->dbh->{ AutoCommit } )
    {
        $dbs->commit;
    }

    my $non_spidered_host_hash = $dbs->find_or_create( 'non_spidered_hosts', { host => $host } );

    $dbs->begin_work();

    # TODO we should probably just use a sql update statement.
    # Transactions don't actually protect us from race conditions.

    $non_spidered_host_hash->{ linked_to_count }++;

    $dbs->update_by_id( 'non_spidered_hosts', $non_spidered_host_hash->{ non_spidered_hosts_id }, $non_spidered_host_hash );

    $dbs->commit;

    $_non_host_link_count++;

    if ( ( $_non_host_link_count % 500 ) == 0 )
    {
        my $site = _get_site_from_url( $url );
        $dbs->create(
            'non_blog_host_links',
            {
                url  => $url,
                host => $host,
                site => $site,
            }
        );
    }

    return;
}

sub _get_possible_blog_uris
{
    my ( $self, $download, $response ) = @_;

    my $url = $response->request->uri;

    my $p = HTML::LinkExtractor->new( undef, $url );
    $p->parse( \$response->content );

    #we only care about links to web pages
    #i.e. '<a href=..' we want to ignore other things such as <img & javascript links
    my $links = [ grep { $_->{ tag } eq 'a' } @{ $p->links } ];

    $links = [ grep { $_->{ href }->scheme eq 'http' } @{ $links } ];

    return map { $_->{ href } } @$links;
}

sub _log_already_processed_url_count
{
    my ( $self ) = @_;

    my $already_processed_urls_for_post = $self->{ already_processed_url_count };

    my $dbs = $self->engine->dbs;

    #eval {
    $dbs->query( "UPDATE url_discovery_counts set num_urls = num_urls + ? where url_discovery_status = 'already_processed'",
        $already_processed_urls_for_post );

    #};

    print STDERR "Updating already processed url counts ($already_processed_urls_for_post)\n";
}

sub _log_not_yet_processed_url_count
{
    my ( $self ) = @_;

    my $not_yet_processed_urls_for_post = $self->{ not_yet_processed_url_count };

    my $dbs = $self->engine->dbs;

    print STDERR "Updating not yet processed url counts ($not_yet_processed_urls_for_post)\n";

    $dbs->query( "UPDATE url_discovery_counts set num_urls = num_urls + ? where url_discovery_status = 'not_yet_processed'",
        $not_yet_processed_urls_for_post );

}

sub _process_links
{
    my ( $self, $download, $response ) = @_;

    #these are post page specific counts;
    $self->{ already_processed_url_count } = 0;
    $self->{ not_yet_processed_url_count } = 0;

    my @uris = $self->_get_possible_blog_uris( $download, $response );

    my @uniq_uris = uniq @uris;

    my $uris_spidered           = 0;
    my $uris_non_blog_host_uris = 0;
    for my $uri ( @uniq_uris )
    {
        if ( $self->_uri_should_be_spidered( $uri ) )
        {

            #print STDERR "XXX spidering blog url '$uri' \n";
            $self->_add_spider_download( $download, $uri );
            $uris_spidered++;
        }
        elsif ( _is_url_non_spidered_host( MediaWords::Crawler::BlogUrlCanonicalizer::get_canonical_blog_url( $uri ) ) )
        {

            #print STDERR "XXX Not spidering non-blog host url '$uri' \n";
            $self->_log_link_to_non_spidered_host( $uri );
            $uris_non_blog_host_uris++;
        }
        else
        {

            #print STDERR "XXX Not spidering blog host url '$uri' \n";
        }
    }

#print STDERR "XXX $uris_spidered spidered urls; $uris_non_blog_host_uris non-blog host uris; " . scalar(@uniq_uris). " total uniq uris\n";

    #Update already processed and newly processed counts in the database
    $self->_log_already_processed_url_count();
    $self->{ already_processed_url_count } = 0;
    $self->_log_not_yet_processed_url_count();
    $self->{ not_yet_processed_url_count } = 0;

    #print STDERR "_process_links_returning\n";
    return;
}

# calling engine
sub engine
{
    if ( $_[ 1 ] )
    {
        $_[ 0 ]->{ engine } = $_[ 1 ];
    }

    return $_[ 0 ]->{ engine };
}

1;
