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
use Tie::Cache::LRU;

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

tie my %cache, 'Tie::Cache::LRU', 10000;

sub translate
{
  my $text = shift;

  if (defined($cache{$text}))
  {
      #say STDERR "Translation for '$text' in cache";
  }
  else
  {
      #say STDERR "Translation for '$text' not in cache";
      $cache{$text} = _translate($text);

  }

  return $cache{$text};
}

1;
