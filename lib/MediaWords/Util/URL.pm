package MediaWords::Util::URL;

use strict;
use warnings;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use Readonly;
use URI;
use URI::QueryParam;
use Regexp::Common qw /URI/;
use MediaWords::Util::Web;
use URI::Escape;
use List::MoreUtils qw/uniq/;

# Regular expressions for invalid "variants" of the resolved URL
Readonly my @INVALID_URL_VARIANT_REGEXES => (

    # Twitter's "suspended" accounts
    qr#^https?://twitter.com/account/suspended#i,
);

# Regular expressions for URL's path that, when matched, mean that the URL is a
# homepage URL
Readonly my @HOMEPAGE_URL_PATH_REGEXES => (

    # Empty path (e.g. http://www.nytimes.com)
    qr#^$#i,

    # One or more slash (e.g. http://www.nytimes.com/, http://m.wired.com///)
    qr#^/+$#i,

    # Limited number of either all-lowercase or all-uppercase (but not both)
    # characters and no numbers, e.g.:
    #
    # * /en/,
    # * /US
    # * /global/,
    # * /trends/explore
    #
    # but not:
    #
    # * /oKyFAMiZMbU
    # * /1uSjCJp
    qr#^[a-z/\-_]{1,18}/?$#,
    qr#^[A-Z/\-_]{1,18}/?$#,

);

# URL shortener hostnames
#
# Sources:
# * http://www.techmaish.com/list-of-230-free-url-shorteners-services/
# * http://longurl.org/services
Readonly my @URL_SHORTENER_HOSTNAMES => qw/
  0rz.tw
  1link.in
  1url.com
  2.gp
  2big.at
  2pl.us
  2tu.us
  2ya.com
  3.ly
  307.to
  4ms.me
  4sq.com
  4url.cc
  6url.com
  7.ly
  a.gg
  a.nf
  a2a.me
  aa.cx
  abbrr.com
  abcurl.net
  ad.vu
  adf.ly
  adjix.com
  afx.cc
  all.fuseurl.com
  alturl.com
  amzn.to
  ar.gy
  arst.ch
  atu.ca
  azc.cc
  b23.ru
  b2l.me
  bacn.me
  bcool.bz
  binged.it
  bit.ly
  bizj.us
  bkite.com
  bloat.me
  bravo.ly
  bsa.ly
  budurl.com
  buk.me
  burnurl.com
  c-o.in
  canurl.com
  chilp.it
  chzb.gr
  cl.lk
  cl.ly
  clck.ru
  cli.gs
  cliccami.info
  clickmeter.com
  clickthru.ca
  clop.in
  conta.cc
  cort.as
  cot.ag
  crks.me
  ctvr.us
  cutt.us
  cuturl.com
  dai.ly
  decenturl.com
  dfl8.me
  digbig.com
  digg.com
  disq.us
  dld.bz
  dlvr.it
  do.my
  doiop.com
  dopen.us
  dwarfurl.com
  dy.fi
  easyuri.com
  easyurl.net
  eepurl.com
  esyurl.com
  eweri.com
  ewerl.com
  fa.b
  fa.by
  fav.me
  fb.me
  fbshare.me
  ff.im
  fff.to
  fhurl.com
  fire.to
  firsturl.de
  firsturl.net
  flic.kr
  flq.us
  fly2.ws
  fon.gs
  freak.to
  fuseurl.com
  fuzzy.to
  fwd4.me
  fwib.net
  g.ro.lt
  gizmo.do
  gl.am
  go.9nl.com
  go.ign.com
  go.usa.gov
  go2.me
  go2cut.com
  goo.gl
  goshrink.com
  gowat.ch
  gri.ms
  gurl.es
  hellotxt.com
  hex.io
  hiderefer.com
  hmm.ph
  hover.com
  href.in
  hsblinks.com
  htxt.it
  huff.to
  hugeurl.com
  hulu.com
  hurl.it
  hurl.me
  hurl.ws
  icanhaz.com
  idek.net
  ilix.in
  inreply.to
  is.gd
  iscool.net
  iterasi.net
  its.my
  ix.lt
  j.mp
  jijr.com
  jmp2.net
  just.as
  kissa.be
  kl.am
  klck.me
  korta.nu
  krunchd.com
  l9k.net
  lat.ms
  liip.to
  liltext.com
  lin.cr
  linkbee.com
  linkbun.ch
  liurl.cn
  ln-s.net
  ln-s.ru
  lnk.gd
  lnk.in
  lnk.ms
  lnkd.in
  lnkurl.com
  loopt.us
  lru.jp
  lt.tl
  lurl.no
  macte.ch
  mash.to
  merky.de
  metamark.net
  migre.me
  minilien.com
  miniurl.com
  minurl.fr
  mke.me
  moby.to
  moourl.com
  mrte.ch
  myloc.me
  myurl.in
  n.pr
  nbc.co
  nblo.gs
  ne1.net
  njx.me
  nn.nf
  not.my
  notlong.com
  nsfw.in
  nutshellurl.com
  nxy.in
  nyti.ms
  o-x.fr
  oc1.us
  om.ly
  omf.gd
  omoikane.net
  on.cnn.com
  on.mktw.net
  onforb.es
  orz.se
  ow.ly
  pd.am
  pic.gd
  ping.fm
  piurl.com
  pli.gs
  pnt.me
  politi.co
  poprl.com
  post.ly
  posted.at
  pp.gg
  profile.to
  ptiturl.com
  pub.vitrue.com
  qicute.com
  qlnk.net
  qte.me
  qu.tc
  quip-art.com
  qy.fi
  r.im
  rb6.me
  read.bi
  readthis.ca
  reallytinyurl.com
  redir.ec
  redirects.ca
  redirx.com
  retwt.me
  ri.ms
  rickroll.it
  riz.gd
  rsmonkey.com
  rt.nu
  ru.ly
  rubyurl.com
  rurl.org
  rww.tw
  s4c.in
  s7y.us
  safe.mn
  sameurl.com
  sdut.us
  shar.es
  sharein.com
  sharetabs.com
  shink.de
  shorl.com
  short.ie
  short.to
  shortlinks.co.uk
  shortna.me
  shorturl.com
  shoturl.us
  shout.to
  show.my
  shrinkify.com
  shrinkr.com
  shrinkster.com
  shrt.fr
  shrt.st
  shrten.com
  shrunkin.com
  shw.me
  simurl.com
  slate.me
  smallr.com
  smsh.me
  smurl.name
  sn.im
  snipr.com
  snipurl.com
  snurl.com
  sp2.ro
  spedr.com
  sqrl.it
  srnk.net
  srs.li
  starturl.com
  sturly.com
  su.pr
  surl.co.uk
  surl.hu
  t.cn
  t.co
  t.lh.com
  ta.gd
  tbd.ly
  tcrn.ch
  tgr.me
  tgr.ph
  thrdl.es
  tighturl.com
  tiniuri.com
  tiny.cc
  tiny.ly
  tiny.pl
  tiny123.com
  tinyarro.ws
  tinylink.in
  tinytw.it
  tinyuri.ca
  tinyurl.com
  tinyvid.io
  tk.
  tl.gd
  tmi.me
  tnij.org
  tnw.to
  tny.com
  to.
  to.ly
  togoto.us
  totc.us
  toysr.us
  tpm.ly
  tr.im
  tr.my
  tra.kz
  traceurl.com
  trunc.it
  turo.us
  tweetburner.com
  twhub.com
  twirl.at
  twit.ac
  twitclicks.com
  twitterpan.com
  twitterurl.net
  twitterurl.org
  twitthis.com
  twiturl.de
  twurl.cc
  twurl.nl
  u.mavrev.com
  u.nu
  u6e.de
  u76.org
  ub0.cc
  ulu.lu
  updating.me
  ur1.ca
  url.az
  url.co.uk
  url.ie
  url360.me
  url4.eu
  urlao.com
  urlborg.com
  urlbrief.com
  urlcover.com
  urlcut.com
  urlenco.de
  urlhawk.com
  urli.nl
  urlkiss.com
  urlot.com
  urlpire.com
  urls.im
  urlshorteningservicefortwitter.com
  urlx.ie
  urlx.org
  urlzen.com
  usat.ly
  use.my
  vb.ly
  vgn.am
  virl.com
  vl.am
  vm.lc
  w3t.org
  w55.de
  wapo.st
  wapurl.co.uk
  wipi.es
  wp.me
  x.se
  x.vu
  xaddr.com
  xeeurl.com
  xr.com
  xrl.in
  xrl.us
  xurl.es
  xurl.jp
  xzb.cc
  y.ahoo.it
  yatuc.com
  ye.pe
  yep.it
  yfrog.com
  yhoo.it
  yiyd.com
  youtu.be
  yuarel.com
  yweb.com
  z0p.de
  zi.ma
  zi.mu
  zi.pe
  zipmyurl.com
  zud.me
  zurl.ws
  zz.gd
  zzang.kr
  ›.ws
  ✩.ws
  ✿.ws
  ❥.ws
  ➔.ws
  ➞.ws
  ➡.ws
  ➨.ws
  ➯.ws
  ➹.ws
  ➽.ws
  /;

# Fixes common URL mistakes (mistypes, etc.)
sub fix_common_url_mistakes($)
{
    my $url = shift;

    return undef unless ( defined( $url ) );

    # Fix broken URLs that look like this: http://http://www.al-monitor.com/pulse
    $url =~ s~(https?://)https?:?//~$1~i;

    # Fix URLs with only one slash after "http" ("http:/www.")
    $url =~ s~(https?:/)(www)~$1/$2~i;

    # replace backslashes with forward
    $url =~ s/\\/\//g;

    return $url;
}

# Returns true if URL is in the "http" ("https") scheme
sub is_http_url($)
{
    my $url = shift;

    unless ( $url )
    {
        # say STDERR "URL is undefined";
        return 0;
    }

    unless ( $url =~ /$RE{URI}{HTTP}{-scheme => '(?:http|https)'}/i )
    {
        # say STDERR "URL does not match URL's regexp";
        return 0;
    }

    my $uri = URI->new( $url )->canonical;

    unless ( $uri->scheme )
    {
        # say STDERR "Scheme is undefined for URL $url";
        return 0;
    }
    unless ( $uri->scheme eq 'http' or $uri->scheme eq 'https' )
    {
        # say STDERR "Scheme is not HTTP(s) for URL $url";
        return 0;
    }

    return 1;
}

# Returns true if URL is homepage (e.g. http://www.wired.com/) and not a child
# page (e.g. http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/)
sub is_homepage_url($)
{
    my $url = shift;

    unless ( $url )
    {
        # say STDERR "URL is empty or undefined.";
        return 0;
    }

    unless ( is_http_url( $url ) )
    {
        # say STDERR "URL is not valid";
        return 0;
    }

    # Remove cruft from the URL first
    eval { $url = normalize_url( $url ); };
    if ( $@ )
    {
        # say STDERR "Unable to normalize URL '$url' before checking if it's a homepage: $@";
        return 0;
    }

    # The shortened URL may lead to a homepage URL, but the shortened URL
    # itself is not a homepage URL
    if ( is_shortened_url( $url ) )
    {
        return 0;
    }

    # If we still have something for a query of the URL after the
    # normalization, always assume that the URL is *not* a homepage
    my $uri = URI->new( $url )->canonical;
    if ( defined $uri->query and $uri->query . '' )
    {
        return 0;
    }

    my $uri_path = $uri->path;
    foreach my $homepage_url_path_regex ( @HOMEPAGE_URL_PATH_REGEXES )
    {
        if ( $uri_path =~ $homepage_url_path_regex )
        {
            return 1;
        }
    }

    return 0;
}

# Returns true if URL is a shortened URL (e.g. with Bit.ly)
sub is_shortened_url($)
{
    my $url = shift;

    unless ( $url )
    {
        # say STDERR "URL is empty or undefined.";
        return 0;
    }

    unless ( is_http_url( $url ) )
    {
        # say STDERR "URL is not valid";
        return 0;
    }

    my $uri = URI->new( $url )->canonical;
    if ( defined $uri->path and ( $uri->path eq '' or $uri->path eq '/' ) )
    {
        # Assume that most of the URL shorteners use something like
        # bit.ly/abcdef, so if there's no path or if it's empty, it's not a
        # shortened URL
        return 0;
    }

    my $uri_host = lc( $uri->host );
    foreach my $url_shortener_hostname ( @URL_SHORTENER_HOSTNAMES )
    {
        if ( $uri_host eq lc( $url_shortener_hostname ) )
        {
            return 1;
        }
    }

    return 0;
}

# Normalize URL:
#
# * Fix common mistypes, e.g. "http://http://..."
# * Run URL through URI->canonical, i.e. standardize URL's scheme and hostname
#   case, remove default port, uppercase all escape sequences, unescape octets
#   that can be represented as plain characters, remove whitespace
#   before / after the URL string)
# * Remove #fragment
# * Remove various ad tracking query parameters, e.g. "utm_source",
#   "utm_medium", "PHPSESSID", etc.
#
# Return normalized URL on success; die() on error
sub normalize_url($)
{
    my $url = shift;

    unless ( $url )
    {
        die "URL is undefined";
    }

    $url = fix_common_url_mistakes( $url );

    unless ( is_http_url( $url ) )
    {
        die "URL is not valid";
    }

    my $uri = URI->new( $url )->canonical;

    # Remove #fragment
    $uri->fragment( undef );

    my @parameters_to_remove;

    # Facebook parameters (https://developers.facebook.com/docs/games/canvas/referral-tracking)
    @parameters_to_remove = (
        @parameters_to_remove,
        qw/ fb_action_ids fb_action_types fb_source fb_ref
          action_object_map action_type_map action_ref_map
          fsrc /
    );

    # metrika.yandex.ru parameters
    @parameters_to_remove = ( @parameters_to_remove, qw/ yclid _openstat / );

    if ( $uri->host =~ /facebook\.com$/i )
    {
        # Additional parameters specifically for the facebook.com host
        @parameters_to_remove = ( @parameters_to_remove, qw/ ref fref hc_location / );
    }

    if ( $uri->host =~ /nytimes\.com$/i )
    {
        # Additional parameters specifically for the nytimes.com host
        @parameters_to_remove = (
            @parameters_to_remove,
            qw/ emc partner _r hp inline smid WT.z_sma bicmp bicmlukp bicmst bicmet abt
              abg /
        );
    }

    if ( $uri->host =~ /livejournal\.com$/i )
    {
        # Additional parameters specifically for the livejournal.com host
        @parameters_to_remove = ( @parameters_to_remove, qw/ thread nojs / );
    }

    if ( $uri->host =~ /google\./i )
    {
        # Additional parameters specifically for the google.[com,lt,...] host
        @parameters_to_remove = ( @parameters_to_remove, qw/ gws_rd ei / );
    }

    # Some other parameters (common for tracking session IDs, advertising, etc.)
    @parameters_to_remove = (
        @parameters_to_remove,
        qw/ PHPSESSID PHPSESSIONID
          cid s_cid sid ncid ir
          ref oref eref
          ns_mchannel ns_campaign ITO
          wprss custom_click source
          feedName feedType
          skipmobile skip_mobile
          altcast_code /
    );

    # Make the sorting default (e.g. on Reddit)
    # Some other parameters (common for tracking session IDs, advertising, etc.)
    push( @parameters_to_remove, 'sort' );

    # Some Australian websites append the "nk" parameter with a tracking hash
    my @nk_values = $uri->query_param( 'nk' );
    foreach my $nk_value ( @nk_values )
    {
        if ( $nk_value =~ /^[0-9a-fA-F]+$/i )
        {
            push( @parameters_to_remove, 'nk' );
            last;
        }
    }

    # Delete the "empty" parameter (e.g. in http://www-nc.nytimes.com/2011/06/29/us/politics/29marriage.html?=_r%3D6)
    push( @parameters_to_remove, '' );

    # Remove cruft parameters
    foreach my $parameter ( @parameters_to_remove )
    {
        $uri->query_param_delete( $parameter );
    }

    my @parameters = $uri->query_param;
    foreach my $parameter ( @parameters )
    {
        # Remove parameters that start with '_' (e.g. '_cid') because they're
        # more likely to be the tracking codes
        if ( $parameter =~ /^_/ )
        {
            $uri->query_param_delete( $parameter );
        }

        # Remove GA parameters, current and future (e.g. "utm_source",
        # "utm_medium", "ga_source", "ga_medium")
        # (https://support.google.com/analytics/answer/1033867?hl=en)
        elsif ( $parameter =~ /^ga_/ or $parameter =~ /^utm_/ )
        {
            $uri->query_param_delete( $parameter );
        }
    }

    return $uri->as_string;
}

# do some simple transformations on a URL to make it match other equivalent
# URLs as well as possible; normalization is "lossy" (makes the whole URL
# lowercase, removes subdomain parts "m.", "data.", "news.", ... in some cases)
sub normalize_url_lossy($)
{
    my $url = shift;

    return undef unless ( $url );

    $url = fix_common_url_mistakes( $url );

    $url = lc( $url );

    # r2.ly redirects through the hostname, ala http://543.r2.ly
    if ( $url !~ /r2\.ly/ )
    {
        $url =~
s/^(https?:\/\/)(m|beta|media|data|image|www?|cdn|topic|article|news|archive|blog|video|search|preview|shop|sports?|act|donate|press|web|photos?|\d+?).?\./$1/i;
    }

    $url =~ s/\#.*//;

    $url =~ s/\/+$//;

    return scalar( URI->new( $url )->canonical );
}

# get the domain of the given URL (sans "www." and ".edu"; see t/URL.t for output examples)
sub get_url_domain($)
{
    my $url = shift;

    $url = fix_common_url_mistakes( $url );

    $url =~ m~https?://([^/#]*)~ || return $url;

    my $host = $1;

    my $name_parts = [ split( /\./, $host ) ];

    my $n = @{ $name_parts } - 1;

    my $domain;
    if ( $host =~ /\.(gov|org|com?)\...$/i )
    {
        # foo.co.uk -> foo.co.uk instead of co.uk
        $domain = join( ".", ( $name_parts->[ $n - 2 ], $name_parts->[ $n - 1 ], $name_parts->[ $n ] ) );
    }
    elsif ( $host =~ /\.(edu|gov)$/i )
    {
        $domain = join( ".", ( $name_parts->[ $n - 2 ], $name_parts->[ $n - 1 ] ) );
    }
    elsif ( $host =~
        /go.com|wordpress.com|blogspot|livejournal.com|privet.ru|wikia.com|feedburner.com|24open.ru|patch.com|tumblr.com/i )
    {
        # identify sites in these domains as the whole host name (abcnews.go.com instead of go.com)
        $domain = $host;
    }
    else
    {
        $domain = join( ".", $name_parts->[ $n - 1 ] || '', $name_parts->[ $n ] || '' );
    }

    return lc( $domain );
}

# given a <meta ...> tag, return the url from the content="url=XXX" attribute.  return undef
# if no such url is found.
sub _get_meta_refresh_url_from_tag
{
    my ( $tag, $base_url ) = @_;

    return undef unless ( $tag =~ m~http-equiv\s*?=\s*?["']\s*?refresh\s*?["']~i );

    my $url;

    if ( $tag =~ m~content\s*?=\s*?"\d*?\s*?;?\s*?URL\s*?=\s*?'(.+?)'~i )
    {
        # content="url='http://foo.bar'"
        $url = $1;
    }
    elsif ( $tag =~ m~content\s*?=\s*?'\d*?\s*?;?\s*?URL\s*?=\s*?"(.+?)"~i )
    {
        # content="url='http://foo.bar'"
        $url = $1;
    }
    elsif ( $tag =~ m~content\s*?=\s*?["']\d*?\s*?;?\s*?URL\s*?=\s*?(.+?)["']~i )
    {
        $url = $1;
    }

    return undef unless ( $url );

    return $url if ( is_http_url( $url ) );

    return URI->new_abs( $url, $base_url )->as_string if ( $base_url );

    return undef;
}

# From the provided HTML, determine the <meta http-equiv="refresh" /> URL (if any)
sub meta_refresh_url_from_html($;$)
{
    my ( $html, $base_url ) = @_;

    while ( $html =~ m~(<\s*?meta.+?>)~gi )
    {
        my $tag = $1;

        my $url = _get_meta_refresh_url_from_tag( $tag, $base_url );

        return $url if ( $url );
    }

    return undef;
}

# From the provided HTML, determine the <link rel="canonical" /> URL (if any)
sub link_canonical_url_from_html($;$)
{
    my ( $html, $base_url ) = @_;

    my $url = undef;
    while ( $html =~ m~(<\s*?link.+?>)~gi )
    {
        my $link_element = $1;

        if ( $link_element =~ m~rel\s*?=\s*?["']\s*?canonical\s*?["']~i )
        {
            if ( $link_element =~ m~href\s*?=\s*?["'](.+?)["']~i )
            {
                $url = $1;
                if ( $url )
                {
                    if ( $url !~ /$RE{URI}/ )
                    {
                        # Maybe it's absolute path?
                        if ( $base_url )
                        {
                            my $uri = URI->new_abs( $url, $base_url );
                            return $uri->as_string;
                        }
                        else
                        {
                            # say STDERR
                            #   "HTML <link rel=\"canonical\"/> found, but the new URL ($url) doesn't seem to be valid.";
                        }
                    }
                    else
                    {
                        # Looks like URL, so return it
                        return $url;
                    }
                }
            }
        }
    }

    return undef;
}

# Fetch the URL, evaluate HTTP / HTML redirects; return URL and data after all
# those redirects; die() on error
sub url_and_data_after_redirects($;$$)
{
    my ( $orig_url, $max_http_redirect, $max_meta_redirect ) = @_;

    unless ( defined $orig_url )
    {
        die "URL is undefined.";
    }

    $orig_url = fix_common_url_mistakes( $orig_url );

    unless ( is_http_url( $orig_url ) )
    {
        die "URL is not HTTP(s): $orig_url";
    }

    my $uri = URI->new( $orig_url )->canonical;

    $max_http_redirect //= 7;
    $max_meta_redirect //= 3;

    my $html = undef;

    for ( my $meta_redirect = 1 ; $meta_redirect <= $max_meta_redirect ; ++$meta_redirect )
    {

        # Do HTTP request to the current URL
        my $ua = MediaWords::Util::Web::UserAgent;

        $ua->max_redirect( $max_http_redirect );

        my $response = $ua->get( $uri->as_string );

        unless ( $response->is_success )
        {
            my @redirects = $response->redirects();
            if ( scalar @redirects + 1 >= $max_http_redirect )
            {
                my @urls_redirected_to;

                my $error_message = "";
                $error_message .= "Number of HTTP redirects ($max_http_redirect) exhausted; redirects:\n";
                foreach my $redirect ( @redirects )
                {
                    push( @urls_redirected_to, $redirect->request()->uri()->canonical->as_string );
                    $error_message .= "* From: " . $redirect->request()->uri()->canonical->as_string . "; ";
                    $error_message .= "to: " . $redirect->header( 'Location' ) . "\n";
                }

                # say STDERR $error_message;

                # Return the original URL (unless we find a URL being a substring of another URL, see below)
                $uri = URI->new( $orig_url )->canonical;

                # If one of the URLs that we've been redirected to contains another URLencoded URL, assume
                # that we're hitting a paywall and the URLencoded URL is the right one
                @urls_redirected_to = uniq @urls_redirected_to;
                foreach my $url_redirected_to ( @urls_redirected_to )
                {
                    my $encoded_url_redirected_to = uri_escape( $url_redirected_to );

                    if ( my ( $matched_url ) = grep /$encoded_url_redirected_to/, @urls_redirected_to )
                    {

#                         say STDERR
# "Encoded URL $encoded_url_redirected_to is a substring of another URL $matched_url, so I'll assume that $url_redirected_to is the correct one.";
                        $uri = URI->new( $url_redirected_to )->canonical;
                        last;

                    }
                }

            }
            else
            {
                # say STDERR "Request to " . $uri->as_string . " was unsuccessful: " . $response->status_line;

                # Return the original URL and give up
                $uri = URI->new( $orig_url )->canonical;
            }

            last;
        }

        my $new_uri = $response->request()->uri()->canonical;
        unless ( $uri->eq( $new_uri ) )
        {
            # say STDERR "New URI: " . $new_uri->as_string;
            $uri = $new_uri;
        }

        # Check if the returned document contains <meta http-equiv="refresh" />
        $html = $response->decoded_content || '';
        my $base_uri = $uri->clone;
        if ( $uri->as_string !~ /\/$/ )
        {
            # In "http://example.com/first/two" URLs, strip the "two" part (but not when it has a trailing slash)
            my @base_uri_path_segments = $base_uri->path_segments;
            pop @base_uri_path_segments;
            $base_uri->path_segments( @base_uri_path_segments );
        }

        my $url_after_meta_redirect = meta_refresh_url_from_html( $html, $base_uri->as_string );
        if ( $url_after_meta_redirect and $uri->as_string ne $url_after_meta_redirect )
        {
            # say STDERR "URL after <meta /> refresh: $url_after_meta_redirect";
            $uri = URI->new( $url_after_meta_redirect )->canonical;

            # ...and repeat the HTTP redirect cycle here
        }
        else
        {
            # No <meta /> refresh, the current URL is the final one
            last;
        }

    }

    return ( $uri->as_string, $html );
}

# for a given set of stories, get all the stories that are source or target merged stories
# in controversy_merged_stories_map.  repeat recursively up to 10 times, or until no new stories are found.
sub _get_merged_stories_ids
{
    my ( $db, $stories_ids, $n ) = @_;

    return [] unless ( @{ $stories_ids } );

    my $stories_ids_list = join( ',', @{ $stories_ids } );

    my $merged_stories_ids = $db->query( <<END )->flat;
select distinct target_stories_id, source_stories_id
    from controversy_merged_stories_map
    where target_stories_id in ( $stories_ids_list ) or source_stories_id in ( $stories_ids_list )
END

    my $all_stories_ids = [ List::MoreUtils::distinct( @{ $stories_ids }, @{ $merged_stories_ids } ) ];

    $n ||= 0;
    if ( ( $n > 10 ) || ( @{ $stories_ids } == @{ $all_stories_ids } ) )
    {
        return $all_stories_ids;
    }
    else
    {
        return _get_merged_stories_ids( $db, $all_stories_ids, $n + 1 );
    }
}

# get any alternative urls for the given url from controversy_merged_stories or controversy_links
sub get_controversy_url_variants
{
    my ( $db, $urls ) = @_;

    my $stories_ids = $db->query( "select stories_id from stories where url in (??)", $urls )->flat;

    my $all_stories_ids = _get_merged_stories_ids( $db, $stories_ids );

    return $urls unless ( @{ $all_stories_ids } );

    my $all_stories_ids_list = join( ',', @{ $all_stories_ids } );

    my $all_urls = $db->query( <<END )->flat;
select distinct url from (
    select redirect_url url from controversy_links where stories_id in ( $all_stories_ids_list )
    union
    select url from controversy_links where stories_id in( $all_stories_ids_list )
    union
    select url from stories where stories_id in ( $all_stories_ids_list )
) q
    where q is not null
END

    return $all_urls;
}

# Given the URL, return all URL variants that we can think of:
# 1) Normal URL (the one passed as a parameter)
# 2) URL after redirects (i.e., fetch the URL, see if it gets redirected somewhere)
# 3) Canonical URL (after removing #fragments, session IDs, tracking parameters, etc.)
# 4) Canonical URL after redirects (do the redirect check first, then strip the tracking parameters from the URL)
# 5) URL from <link rel="canonical" /> (if any)
# 6) Any alternative URLs from controversy_merged_stories or controversy_links
sub all_url_variants($$)
{
    my ( $db, $url ) = @_;

    unless ( defined $url )
    {
        die "URL is undefined";
    }

    $url = fix_common_url_mistakes( $url );

    unless ( is_http_url( $url ) )
    {
        my @urls = ( $url );
        return @urls;
    }

    # Get URL after HTTP / HTML redirects
    my ( $url_after_redirects, $data_after_redirects ) = url_and_data_after_redirects( $url );

    my %urls = (

        # Normal URL (don't touch anything)
        'normal' => $url,

        # Normal URL after redirects
        'after_redirects' => $url_after_redirects,

        # Canonical URL
        'normalized' => normalize_url( $url ),

        # Canonical URL after redirects
        'after_redirects_normalized' => normalize_url( $url_after_redirects )
    );

    # If <link rel="canonical" /> is present, try that one too
    if ( defined $data_after_redirects )
    {
        my $url_link_rel_canonical = link_canonical_url_from_html( $data_after_redirects, $url_after_redirects );
        if ( $url_link_rel_canonical )
        {
            # say STDERR "Found <link rel=\"canonical\" /> for URL $url_after_redirects " .
            #   "(original URL: $url): $url_link_rel_canonical";

            $urls{ 'after_redirects_canonical' } = $url_link_rel_canonical;
        }
    }

    # If URL gets redirected to the homepage (e.g.
    # http://m.wired.com/threatlevel/2011/12/sopa-watered-down-amendment/ leads
    # to http://www.wired.com/), don't use those redirects
    unless ( is_homepage_url( $url ) )
    {
        foreach my $key ( keys %urls )
        {
            if ( is_homepage_url( $urls{ $key } ) )
            {
                say STDERR "URL $url got redirected to $urls{$key} which looks like a homepage, so I'm skipping that.";
                delete $urls{ $key };
            }
        }
    }

    my $distinct_urls = [ List::MoreUtils::distinct( values( %urls ) ) ];

    my $all_urls = get_controversy_url_variants( $db, $distinct_urls );

    # Remove URLs that can't be variants of the initial URL
    foreach my $invalid_url_variant_regex ( @INVALID_URL_VARIANT_REGEXES )
    {
        $all_urls = [ grep { !/$invalid_url_variant_regex/ } @{ $all_urls } ];
    }

    return @{ $all_urls };
}

# Extract http(s):// URLs from a string
# Returns arrayref of unique URLs in a string, die()s on error
sub http_urls_in_string($)
{
    my $string = shift;

    unless ( defined( $string ) )
    {
        die "String is undefined.";
    }

    my @urls = $string =~ /($RE{URI}{HTTP}{-scheme => '(?:http|https)'})/ig;
    @urls = uniq @urls;

    return \@urls;
}

1;
