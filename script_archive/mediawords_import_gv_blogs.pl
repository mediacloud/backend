#!/usr/bin/env perl
#
# Import gv_blogs.txt as media sources
#
# Usage: ./mediawords_import_gv_blogs.pl --input_file=~/Desktop/gv-blogs.xml
#        - or -
#        ./mediawords_import_gv_blogs.pl \
#            --input_file=~/Desktop/gv-blogs.xml \
#            --collection_tag=gv_blogs_20130329
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use utf8;

use XML::TreePP;
use Data::Dumper;
use Getopt::Long;
use Encode;
use MediaWords::DB;
use MediaWords::Util::Tags;
use Text::Iconv;
use Data::Validate::URI qw(is_uri);
use URI;

# Strip string from whitespace
sub _strip_string
{
    my $string = shift;
    $string =~ s/^\s+//;
    $string =~ s/\s+$//;
    return $string;
}

# Don't leave spaces in tags, make lowercase too
sub _tagify_string
{
    my $string = shift;
    $string = _strip_string( $string );
    $string =~ s/\s/_/gs;
    $string = lc( $string );
    $string = encode( 'UTF-8', $string );
    return $string;
}

# Decode a single strangely encoded line
my $iconv = Text::Iconv->new( 'utf8', 'iso-8859-1' );

sub _decode_line($)
{
    my $line = shift;

    $line = decode( 'utf8', $iconv->convert( $line ) );
    return $line;
}

# Normalize URL (add slash to the end) or return undef if URL is invalid
sub _normalize_url($)
{

    # Regexp::Common::URI doesn't work with IDN URLs (such as "http://президент.рф")
    my $url = shift;
    unless ( is_uri( $url ) )
    {

        # Russian IDN?
        unless ( $url =~ /^.+?\.рф$/ or $url =~ /^.+?\.испытание$/ )
        {
            return undef;
        }
    }

    my $uri = URI->new( $url );
    unless ( $uri->scheme )
    {
        return undef;
    }

    return $uri->canonical . '';
}

# Stoplist generator
sub main
{
    binmode( STDOUT, ':utf8' );
    binmode( STDERR, ':utf8' );

    my $input_file     = undef;                  # Input file to read gv-blogs.txt from
    my $collection_tag = 'gv_blogs_20130329';    # Collection tag to add to every medium

    my Readonly $usage = "Usage: $0" . ' --input_file=gv-blogs.txt' . ' [--collection_tag=gv_blogs_20130329]';

    GetOptions(
        'input_file=s'     => \$input_file,
        'collection_tag:s' => \$collection_tag,
    ) or die "$usage\n";
    die "$usage\n" unless ( $input_file and $collection_tag );

    say STDERR "starting --  " . localtime();

    my $dbis = MediaWords::DB::connect_to_db;

    # Start transaction
    $dbis->begin_work;

    # Manual exceptions
    my $exceptions = {
        'dadolin.blogspot.com, tetum: http:,East Timor,1,'            => 'dadolin.blogspot.com,East Timor,1,',
        'panl10n.net,%20http,Pakistan,1,'                             => 'panl10n.net,Pakistan,1,',
        'dadolinlorosae.blogspot.com and galole: http:,East Timor,1,' => 'dadolinlorosae.blogspot.com,East Timor,1,',
        'rationalrepublic,blogspot.com,Syria,1,Lebanon,1,'            => 'rationalrepublic.blogspot.com,Syria,1,Lebanon,1,',
'http:,Venezuela,1,United Kingdom,1,Guinea,1,Jamaica,1,Israel,1,Palestine,1,Colombia,1,Sudan,1,Namibia,1,U.S.A.,1,China,1,Denmark,1,'
          => '',
'blogger.com,Egypt,1,Dominican Republic,1,Syria,1,Uruguay,3,Turkey,1,Ghana,1,Morocco,1,New Zealand,2,Chile,1,Palestine,1,Uzbekistan,1,Mozambique,1,France,1,Saudi Arabia,1,Argentina,1,Oman,1,Israel,1,U.S.A.,2,Fiji,2,'
          => '',

        # looks like numeric IP but it isn't
        '200558,Cameroon,1,'          => '',
        '.chinadaily.com.cn,China,1,' => 'chinadaily.com.cn,China,1,',
        '.irna.ir,Iran,1,'            => 'irna.ir,Iran,1,',
        '.kandydaci2009.pl,Slovakia,1,Hungary,1,Poland,1,Czech Republic,1,' =>
          'kandydaci2009.pl,Slovakia,1,Hungary,1,Poland,1,Czech Republic,1,',
        ".cocolog-suruga.com,Japan,1,"                         => "cocolog-suruga.com,Japan,1,",
        ".thedailystar.net,Bangladesh,1,"                      => "thedailystar.net,Bangladesh,1,",
        ".esmas.com,Mexico,1,"                                 => "esmas.com,Mexico,1,",
        ".ttcn.ne.jp,U.S.A.,1,Japan,1,"                        => "ttcn.ne.jp,U.S.A.,1,Japan,1,",
        "&#8221; part of url:<,Russia,1,"                      => "",
        ".ee.ntu.edu.tw,Taiwan (ROC),1,"                       => "ee.ntu.edu.tw,Taiwan (ROC),1,",
        ".nhk.or.jp,U.S.A.,1,Japan,1,"                         => "nhk.or.jp,U.S.A.,1,Japan,1,",
        ".voanews.com,Russia,1,Madagascar,3,Niger,1,Guinea,1," => "voanews.com,Russia,1,Madagascar,3,Niger,1,Guinea,1,",
        ".hk.apple.nextmedia.com,China,1,"                     => "hk.apple.nextmedia.com,China,1,",
        ".camara.gov.br,Brazil,1,"                             => "camara.gov.br,Brazil,1,",
        ".niaid.nih.gov,U.S.A.,1,Thailand,1,"                  => "niaid.nih.gov,U.S.A.,1,Thailand,1,",
        ".ids.ac.uk,Germany,1,Guatemala,1,Iceland,1,Venezuela,1,Poland,1,Mexico,1,Cambodia,1,India,1,Brazil,1," =>
          "ids.ac.uk,Germany,1,Guatemala,1,Iceland,1,Venezuela,1,Poland,1,Mexico,1,Cambodia,1,India,1,Brazil,1,",
        ".ac-toulouse.fr,France,1,"                                => "ac-toulouse.fr,France,1,",
        ".abkhaziya.net,Russia,1,Georgia,1,"                       => "abkhaziya.net,Russia,1,Georgia,1,",
        ".folha.uol.com.br,Honduras,1,Brazil,1,"                   => "folha.uol.com.br,Honduras,1,Brazil,1,",
        ".livejournal.com,Russia,1,"                               => "",
        ".ohchr.org,Egypt,1,"                                      => "ohchr.org,Egypt,1,",
        ".beppegrillo.it,Italy,1,"                                 => "beppegrillo.it,Italy,1,",
        'zhanglifan.blog.sohu.com>his own blog<,China,1,'          => 'zhanglifan.blog.sohu.com,China,1,',
        'moe.edu.cn>the ministry of education of prc<,China,1,'    => 'moe.edu.cn,China,1,',
        'wvw. nacion.com,Costa Rica,1,'                            => 'www.nacion.com,Costa Rica,1,',
        'reflexiums.wordpress.com<p class=,Madagascar,1,U.S.A.,1,' => 'reflexiums.wordpress.com,Madagascar,1,U.S.A.,1,',
'proza.com.ua) has been shut down by its us host for displaying &#8216;child pornography&#39;&#8221; - and that &#8220;pavel gudimov&#39;s ya gallery in kiev has been set fire to after the presentation and discussion there of a gay literary anthology.&#8221;<,Ukraine,1,'
          => 'proza.com.ua,Ukraine,1,',
        'beijinghaze.blogspot.com>beijing haze<,China,1,' => 'beijinghaze.blogspot.com,China,1,',
        'iwanshi.vip.bokee.com>shi sansheng<,China,1,'    => 'iwanshi.vip.bokee.com',
        '0101hk.tweetwally.com>tweet-wall<,Hong Kong (China),1,China,1,' =>
          '0101hk.tweetwally.com,Hong Kong (China),1,China,1,',
        'renhaiyong.vip.bokee.com>ren haiyong<,China,1,'              => 'renhaiyong.vip.bokee.com,China,1,',
        'cnbloggercon.org>chinese blogger conference<,China,1,'       => 'cnbloggercon.org,China,1,',
        'ww&lt;a href=,Qatar,1,'                                      => '',
        'berlintwitterwall.com>berlintwitterwall<,Germany,1,China,1,' => 'berlintwitterwall.com,Germany,1,China,1,',
        'threatened.globalvoicesonline.org>threatened voices<,Egypt,1,Lebanon,1,' =>
          'threatened.globalvoicesonline.org,Egypt,1,Lebanon,1,',
        'hailing.vip.bokee.com>hailing<,China,1,' => 'hailing.vip.bokee.com,China,1,',
        'eglug.org many new faces at the #installfest after 6 years and most founders gone yet still rocking.<,Egypt,1,' =>
          'eglug.org,Egypt,1,',
        'sharek.eg<br ,Egypt,1,'                            => 'sharek.eg,Egypt,1,',
        'yfotu.blogspot.com>yfotu<,Taiwan (ROC),1,China,1,' => 'yfotu.blogspot.com,Taiwan (ROC),1,China,1,',
    };

    open( GVBLOGS, $input_file ) or die "Unable to open input file '%input_file': $!\n";
    while ( <GVBLOGS> )
    {

        chomp;

        $_ = _decode_line( _strip_string( $_ ) );

        if ( exists $exceptions->{ $_ } )
        {
            $_ = $exceptions->{ $_ };
        }

        # Skip empty lines
        next unless $_;

        my @line = split( ',' );
        if ( $#line % 2 != 0 )
        {
            die "Wrong number of entries in line: $_\n";
        }
        foreach my $part ( @line )
        {
            die "Empty part: $_\n" unless $part;
        }

        # A lot of "ghanaexpo.com<,Nigeria,1," URLs
        $line[ 0 ] =~ s/(^.+?)<$/$1/;

        my $blog = {
            name                => _strip_string( $line[ 0 ] ),
            url                 => 'http://' . _strip_string( $line[ 0 ] ),
            country_counts      => {},
            total_country_count => 0,
        };

        # Validate URL
        $blog->{ url } = _normalize_url( $blog->{ url } );
        unless ( $blog->{ url } )
        {
            die "URL is invalid for line: $_\n";
        }

        # Read line
        for ( my $x = 0 ; $x < $#line / 2 ; ++$x )
        {
            my $country       = _strip_string( $line[ ( $x * 2 ) + 1 ] );
            my $country_count = _strip_string( $line[ ( $x * 2 ) + 2 ] ) + 0;

            if ( $blog->{ country_counts }->{ $country } )
            {
                die "Country '$country' is already set for line: $_\n";
            }
            unless ( $country_count )
            {
                die "Country count is 0 for line: $_\n";
            }

            $blog->{ country_counts }->{ $country } = $country_count;
            $blog->{ total_country_count } += $country_count;
        }

        # Prepare media to add
        my $media_to_add = {
            name        => $blog->{ name },
            url         => $blog->{ url },
            moderated   => 'f',
            feeds_added => 'f',
        };
        my $media_tags_to_add = [

            # Blanket tag for gv_blogs.txt media
            'collection:' . _tagify_string( $collection_tag ),
        ];

        my $majority_country_found = 0;
        foreach my $country ( keys $blog->{ country_counts } )
        {
            if ( $blog->{ country_counts }->{ $country } * 2 > $blog->{ total_country_count } )
            {
                push( $media_tags_to_add, 'gv_country:' . _tagify_string( $country ) );
                $majority_country_found = 1;
            }
        }
        unless ( $majority_country_found )
        {
            push( $media_tags_to_add, 'gv_country:international' );
        }

        # Create / fetch media
        my $medium = undef;
        if (
            $medium = $dbis->query(
                <<"EOF",
            SELECT *
            FROM media
            WHERE name = ? OR url = ?
EOF
                $media_to_add->{ name }, $media_to_add->{ url }
            )->hash
          )
        {
            print STDERR "Using existing medium with duplicate title '" .
              $media_to_add->{ name } . "' or URL '" . $media_to_add->{ url } . "'.\n";
        }
        else
        {
            $medium = $dbis->create( 'media', $media_to_add );
        }

        for my $tag_set_and_tag ( @{ $media_tags_to_add } )
        {

            # Create / fetch tag
            my $tag = MediaWords::Util::Tags::lookup_or_create_tag( $dbis, $tag_set_and_tag );
            unless ( $tag )
            {
                $dbis->rollback;
                die "Unable to create / fetch tag '$tag_set_and_tag'.\n";
            }

            # Map media to a tag
            unless (
                $dbis->find_or_create(
                    'media_tags_map', { tags_id => $tag->{ tags_id }, media_id => $medium->{ media_id } }
                )
              )
            {
                $dbis->rollback;
                die "Unable to assign '$tag_set_and_tag' to media '" .
                  $medium->{ name } . "' (" . $medium->{ media_id } . ").\n";
            }

        }

        print STDERR "Added / updated media '" . $medium->{ name } . "'\n";
    }

    close( GVBLOGS );

    print STDERR "Committing...\n";
    $dbis->commit;

    say STDERR "finished --  " . localtime();
}

main();
