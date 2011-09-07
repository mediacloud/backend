package Lingua::EN::Sentence::MediaWords;

# local, optimized version of Lingua::EN::Sentence

#==============================================================================
#
# Pragmas
#
#==============================================================================
require 5.005_03;
use strict;
use POSIX qw(locale_h);
use utf8;
use Data::Dumper;

#==============================================================================
#
# Modules
#
#==============================================================================
require Exporter;

use Regexp::Optimizer;

#==============================================================================
#
# Public globals
#
#==============================================================================
use vars qw/$VERSION @ISA @EXPORT_OK $EOS $LOC $AP $P $PAP @ABBREVIATIONS/;
use Carp qw/cluck/;

$VERSION = '0.25';

# LC_CTYPE now in locale "French, Canada, codeset ISO 8859-1"
$LOC = setlocale( LC_CTYPE, "fr_CA.ISO8859-1" );
use locale;

@ISA       = qw( Exporter );
@EXPORT_OK = qw( get_sentences
  add_acronyms get_acronyms set_acronyms
  get_EOS set_EOS);

$EOS = "\001";
$P   = q/[\.!?]/;                  ## PUNCTUATION
$AP  = q/(?:'|"|»|\)|\]|\})?/;    ## AFTER PUNCTUATION
$PAP = $P . $AP;

my @PEOPLE = ( 'jr', 'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', "sens?", "reps?", 'gov', "attys?", 'supt', 'det', 'rev' );

my @ARMY       = ( 'col',  'gen',  'lt',   'cmdr', 'adm', 'capt', 'sgt', 'cpl', 'maj' );
my @INSTITUTES = ( 'dept', 'univ', 'assn', 'bros' );
my @COMPANIES  = ( 'inc',  'ltd',  'co',   'corp' );

# my @PLACES = ( 'arc', 'al', 'ave', "blv?d", 'cl', 'ct', 'cres', 'dr', "expy?",
#       'dist', 'mt', 'ft',
#       "fw?y", "hwa?y", 'la', "pde?", 'pl', 'plz', 'rd', 'st', 'tce',
#       'Ala' , 'Ariz', 'Ark', 'Cal', 'Calif', 'Col', 'Colo', 'Conn',
#       'Del', 'Fed' , 'Fla', 'Ga', 'Ida', 'Id', 'Ill', 'Ind', 'Ia',
#       'Kan', 'Kans', 'Ken', 'Ky' , 'La', 'Me', 'Md', 'Is', 'Mass',
#       'Mich', 'Minn', 'Miss', 'Mo', 'Mont', 'Neb', 'Nebr' , 'Nev',
#       'Mex', 'Okla', 'Ok', 'Ore', 'Penna', 'Penn', 'Pa'  , 'Dak',
#       'Tenn', 'Tex', 'Ut', 'Vt', 'Va', 'Wash', 'Wis', 'Wisc', 'Wy',
#       'Wyo', 'USAFA', 'Alta' , 'Man', 'Ont', 'Qué', 'Sask', 'Yuk');
my @PLACES = (
    'arc', 'al', 'ave',  "blv?d", 'cl', 'ct',   'cres', 'dr',  "expy?", 'dist',
    'mt',  'ft', "fw?y", "hwa?y", 'la', "pde?", 'pl',   'plz', 'rd',    'st'
);
my @MONTHS = ( 'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec', 'sept' );
my @MISC = ( 'vs', 'etc', 'no', 'esp' );

my @RU = ( 'ул', 'г', 'гор', 'г-жа' );

my @ABBREVIATIONS = ( @PEOPLE, @ARMY, @INSTITUTES, @COMPANIES, @PLACES, @MONTHS, @MISC, @RU );
my $ABBREVIATIONS_STRING = '(:?' . join( '|', @ABBREVIATIONS ) . ')';
my $ABBREVIATIONS_RE = Regexp::Optimizer->new->optimize( qr/$ABBREVIATIONS_STRING/iso );

#==============================================================================
#
# Public methods
#
#==============================================================================

#------------------------------------------------------------------------------
# get_sentences - takes text input and splits it into sentences.
# A regular expression cuts viciously the text into sentences,
# and then a list of rules (some of them consist of a list of abbreviations)
# is applied on the marked text in order to fix end-of-sentence markings on
# places which are not indeed end-of-sentence.
#------------------------------------------------------------------------------
sub get_sentences
{
    my ( $text ) = @_;

    return [] unless defined $text;

    # this prevents a regexp bug from hanging the program in remove_false_end_of_sentence (see comement in function)
	$text =~ s/[^\n[:alnum:][:punct:]]+/ /g;

        #Further workaround for remove_false_end_of_sentence bug: add EOS for double newline then purge newlines
        #For some reason we need to be this here instead in first_sentence_breaking
        $text =~ s/\n\s*\n/\n\n/gso;
        $text =~ s/\n\n\n*/\n\n/gso;
        $text =~ s/\n\n/$EOS/gso;
	$text =~ s/\n/ /g;
	$text =~ s/\s+/ /g;

	# the above regexp and html stripping often leave a space before the period at the end of a sentence
	$text =~ s/ +\./\./g;
	
	# we see lots of cases of missing spaces after sentence ending periods
	$text =~ s/([[:lower:]])\.([[:upper:]])/$1. $2/g;
	
	my $marked_text = first_sentence_breaking($text);    

	$marked_text =~ s/[^$EOS[:alnum:][:punct:]]+/ /g;

	my $fixed_marked_text = remove_false_end_of_sentence($marked_text);
	$fixed_marked_text = split_unsplit_stuff($fixed_marked_text);
	my @sentences = split(/$EOS/,$fixed_marked_text);
	my $cleaned_sentences = clean_sentences(\@sentences);
	
	return $cleaned_sentences;
}

#------------------------------------------------------------------------------
# add_acronyms - user can add a list of acronyms/abbreviations.
#------------------------------------------------------------------------------
sub add_acronyms
{
    push @ABBREVIATIONS, @_;
}

#------------------------------------------------------------------------------
# get_acronyms - get defined list of acronyms.
#------------------------------------------------------------------------------
sub get_acronyms
{
    return @ABBREVIATIONS;
}

#------------------------------------------------------------------------------
# set_acronyms - run over the predefined acronyms list with your own list.
#------------------------------------------------------------------------------
sub set_acronyms
{
    @ABBREVIATIONS = @_;
}

#------------------------------------------------------------------------------
# get_EOS - get the value of the $EOS (end-of-sentence mark).
#------------------------------------------------------------------------------
sub get_EOS
{
    return $EOS;
}

#------------------------------------------------------------------------------
# set_EOS - set the value of the $EOS (end-of-sentence mark).
#------------------------------------------------------------------------------
sub set_EOS
{
    my ( $new_EOS ) = @_;
    if ( not defined $new_EOS )
    {
        cluck "Won't set \$EOS to undefined value!\n";
        return $EOS;
    }
    return $EOS = $new_EOS;
}

#------------------------------------------------------------------------------
# set_locale - set the value of the locale.
#
#		Revceives language locale in the form
#			language.country.character-set
#		for example:
#				"fr_CA.ISO8859-1"
#		for Canadian French using character set ISO8859-1.
#
#		Returns a reference to a hash containing the current locale
#		formatting values.
#		Returns undef if got undef.
#
#
#               The following will set the LC_COLLATE behaviour to
#               Argentinian Spanish. NOTE: The naming and avail­
#               ability of locales depends on your operating sys­
#               tem. Please consult the perllocale manpage for how
#               to find out which locales are available in your
#               system.
#
#                       $loc = set_locale( "es_AR.ISO8859-1" );
#
#
#		This actually does this:
#
#			$loc = setlocale( LC_ALL, "es_AR.ISO8859-1" );
#------------------------------------------------------------------------------
sub set_locale
{
    my ( $new_locale ) = @_;
    if ( not defined $new_locale )
    {
        cluck "Won't set locale to undefined value!\n";
        return undef;
    }
    $LOC = setlocale( LC_CTYPE, $new_locale );
    return $LOC;
}

#==============================================================================
#
# Private methods
#
#==============================================================================

sub _split_into_chunks
{
    my ( $text ) = @_;

    my $string_length = length($text);

    my $pos = 0;
    
    my $ret = [];

    my $segment_length = 1000;

    while ( $pos < $string_length )
      {
	 my $segment = substr $text, $pos, $segment_length;

	 print Dumper( $segment );

	 $pos += $segment_length;

	 push @{$ret}, $segment;
      }

    print "DUMPERING\n";
    print  Dumper ( [$ret] );
    print "Dumped\n";

    return $ret;
}

sub _apply_dangerous_regex
{
    my ( $text ) = @_;

    print "starting _apply_dangerous_regex\n";
    print Dumper( $text );
    print "\n";

    $text =~ s/([^-\w]\w[\.!?])\001/$1/sgo; 

    return $text;
}

## Please email me any suggestions for optimizing these RegExps.
sub remove_false_end_of_sentence
{
    my ( $marked_segment ) = @_;

##	## don't do u.s.a.
##	$marked_segment=~s/(\.\w$PAP)$EOS/$1/sg;

    $marked_segment =~ s/([^-\w]\w$PAP\s)$EOS/$1/sgo;

    # this hangs unless we do the $text =~ s/[^[:alnum:][:punct:]]+/ /g; above

    #my $o = Regexp::Optimizer->new;
    #my $re = $o->optimize( /([^-\w]\w$P)$EOS/ );
    #my $re_hang = /([^-\w]\w$P)$EOS/so ;


    #$P   = q/[\.!?]/;            

    #$marked_segment =~ s/([^-\w]\w[\.!?])\001/$1/sgo;

    $marked_segment = join '', map { _apply_dangerous_regex( $_ ) }  @ {_split_into_chunks( $marked_segment )};

#    $marked_segment =~ s/([^-\w]\w$P)$EOS/$1/sgo;

   # $marked_segment =~ s/$re_hang/$1/sgo;

    # don't split after a white-space followed by a single letter followed
    # by a dot followed by another whitespace.
    #
    # FIXME - hal: this is hanging on non-ascii characters and I can't figure out why so
    # I'm just commenting it out
    #
    #$marked_segment=~s/(\s\w\.\s+)$EOS/$1/sgo;

    # fix: bla bla... yada yada
    $marked_segment =~ s/(\.\.\. )$EOS([[:lower:]])/$1$2/sgo;

    # fix "." "?" "!"
    $marked_segment =~ s/(['"“]$P['"”]\s+)$EOS/$1/sgo;
    ## fix where abbreviations exist
    #foreach (@ABBREVIATIONS) { $marked_segment=~s/(\b$_$PAP\s)$EOS/$1/isgo; }

    # use optimize to improve performance of this regexp, which eats up almost
    # all of the time of sentence parsing -hal
    $marked_segment =~ s/(\b$ABBREVIATIONS_RE$PAP\s)$EOS/$1/isgo;

    # don't break after quote unless its a capital letter.
    $marked_segment =~ s/(["']\s*)$EOS(\s*[[:lower:]])/$1$2/sgo;

    # don't break: text . . some more text.
    $marked_segment =~ s/(\s\.\s)$EOS(\s*)/$1$2/sgo;

    $marked_segment =~ s/(\s$PAP\s)$EOS/$1/sgo;
    return $marked_segment;
}

sub split_unsplit_stuff
{
    my ( $text ) = @_;

    $text =~ s/(\D\d+)($P)(\s+)/$1$2$EOS$3/sgo;
    $text =~ s/($PAP\s)(\s*\()/$1$EOS$2/gso;
    $text =~ s/('\w$P)(\s)/$1$EOS$2/gso;

    $text =~ s/(\sno\.)(\s+)(?!\d)/$1$EOS$2/giso;

##	# split where single capital letter followed by dot makes sense to break.
##	# notice these are exceptions to the general rule NOT to split on single
##	# letter.
##	# notice also that sibgle letter M is missing here, due to French 'mister'
##	# which is representes as M.
##	#
##	# the rule will not split on names begining or containing
##	# single capital letter dot in the first or second name
##	# assuming 2 or three word name.
##	$text=~s/(\s[[:lower:]]\w+\s+[^[[:^upper:]M]\.)(?!\s+[[:upper:]]\.)/$1$EOS/sg;

    # add EOS when you see "a.m." or "p.m." followed by a capital letter.
    $text =~ s/([ap]\.m\.\s+)([[:upper:]])/$1$EOS$2/gs;

    return $text;
}

sub clean_sentences
{
    my ( $sentences ) = @_;
    my $cleaned_sentences;
    foreach my $s ( @$sentences )
    {
        next if not defined $s;
        next if $s !~ m/\w+/;
        $s =~ s/^\s*//;
        $s =~ s/\s*$//;
##			$s=~s/\s+/ /g;
        push @$cleaned_sentences, $s;
    }
    return $cleaned_sentences;
}

sub first_sentence_breaking
{
    my ( $text ) = @_;
    #$text =~ s/\n\s*\n/$EOS/gso;       ## double new-line means a different sentence.
    $text =~ s/($PAP\s)/$1$EOS/gso;
    $text =~ s/(\s\w$P)/$1$EOS/gso;    # breake also when single letter comes before punc.
    return $text;
}

#==============================================================================
#
# Return TRUE
#
#==============================================================================

1;
