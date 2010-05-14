package MediaWords::Util::Translate;

# various functions for manipulating html

require      Exporter;

our @ISA       = qw(Exporter);
our @EXPORT    = qw(translate);  

# various functions for editing feed and medium tags

use strict;
use WebService::Google::Language;
use Perl6::Say;
use Text::Trim;
use CHI;

my $media_cloud_root_dir;

BEGIN
{
    use FindBin;
    my $source_file_dir = "$FindBin::Bin";
    $media_cloud_root_dir = "$source_file_dir/../../../";
}

my $cache = CHI->new(
		     driver     => 'FastMmap',
		     expires_in => '1 week',
		     expires_variance => '0.1',
		     root_dir   => "$media_cloud_root_dir/cache/translate",
		     cache_size => '3m'
		    );

sub _translate
{
    my $original_text = shift;

    say STDERR "starting translate";

    my $service = WebService::Google::Language->new(
	'referer' => 'http://example.com/',
	'src'     => 'ru',
	'dest'    => 'en',
	);

    my $text = $original_text;

    trim($text);

    return $original_text unless $text;

    say STDERR "sending request for '$text'";
    
    my $result = $service->translate(substr($text, 0, 500));

    say STDERR "got result";


    if ($result->error) {
	say STDERR $result->message;
	say STDERR 'error translating';
	return $text;
    }
    else
    {
	say STDERR 'no error translating';
	say STDERR $result->translation;
	return $result->translation;
    }
}

sub translate
{
  my $text = shift;

  my $ret = $cache->get($text);
  if ( !defined( $ret) ) {
    #say STDERR "Translation for '$text' not in cache";
    $ret =  _translate($text);
    $cache->set( $text, $ret );
  }
  else
  {
     #say STDERR "Translation for '$text' in cache";
  }

  return $ret;
}

1;
