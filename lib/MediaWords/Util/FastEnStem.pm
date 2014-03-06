package MediaWords::Util::FastEnStem;

# optimized version of Lingua::Stem::EN::stem_in_place that takes advantage of the
# fact that we know words we are stemming are already lower case, have no punctuation,
# and don't need caching

use strict;

my $syl = '[aeiou]*[^aeiou][^aeiouy]*[aeiouy]';
my $hasvow = '[^aeiouy]*([aeiou]|y.)';

# optimized version of Lingua::Stem::EN.
# assumes that the words are lowercase, have no punctuation, and don't need caching
sub stem_in_place
{
    my $words = \@_;
    

    local( $_ );

    foreach (@$words) 
    {
        #  Reverse the word so we can easily apply pattern matching to the end:
        $_ = reverse $_;
    
        #  Step 1a: plurals -- sses->ss, ies->i, ss->ss, s->0
    
        m!^s! && ( s!^se(ss|i)!$1! || s!^s([^s])!$1! );
    
        #  Step 1b: participles -- SYLeed->SYLee, VOWed->VOW, VOWing->VOW;
        #  but ated->ate etc
    
        s!^dee($syl)!ee$1!o ||
        (
    	s!^(de|gni)($hasvow)!$2!o &&
    	(
    	    #  at->ate, bl->ble, iz->ize, is->ise
    	    s!^(ta|lb|[sz]i)!e$1! ||			# ** ise as well as ize
    	    #  CC->C (C consonant other than l, s, z)
    	    s!^([^aeioulsz])\1!$1! ||
    	    #  (m=1) CVD->CVDe (C consonant, V vowel, D consonant not w, x, y)
    	    s!^([^aeiouwxy][aeiouy][^aeiou]+)$!e$1!
    	)
        );
    
        #  Step 1c: change y to i: happy->happi, sky->sky
    
        s!^y($hasvow)!i$1!o;
    
        #  Step 2: double and triple suffices (part 1)
    
        #  Switch on last three letters (fails harmlessly if subroutine undefined) --
        #  thanks to Ian Phillipps <ian@dial.pipex.com> who wrote
        #    CPAN authors/id/IANPX/Stem-0.1.tar.gz 
        #  for suggesting the replacement of
        #    eval( '&S2' . unpack( 'a3', $_ ) );
        #  (where the eval ignores undefined subroutines) by the much faster
        #    eval { &{ 'S2' . substr( $_, 0, 3 ) } };
        #  But the following is slightly faster still:

        { 
            no strict 'refs';
            
            my $sub;
    
            #  Step 3: double and triple suffices, etc (part 2)

            &$sub if defined &{ $sub = '_S2' . substr( $_, 0, 3 ) };
    
            #  Step 3: double and triple suffices, etc (part 2)
    
            &$sub if defined &{ $sub = '_S3' . substr( $_, 0, 3 ) };
    
            #  Step 4: single suffices on polysyllables
    
            &$sub if defined &{ $sub = '_S4' . substr( $_, 0, 2 ) };
   
        }
        #  Step 5a: tidy up final e -- probate->probat, rate->rate; cease->ceas
    
        m!^e! && ( s!^e($syl$syl)!$1!o ||
    
    	# Porter's ( m=1 and not *o ) E where o = cvd with d a consonant
    	# not w, x or y:
    
    	! m!^e[^aeiouwxy][aeiouy][^aeiou]! &&	# not *o E
    	s!^e($syl[aeiouy]*[^aeiou]*)$!$1!o	# m=1
        );
    
        #  Step 5b: double l -- controll->control, roll->roll
        #  ** Note correction: Porter has m>1 here ($syl$syl), but it seems m>0
        #  ($syl) is wanted to strip an l off controll.
    
        s!^ll($syl)!l$1!o;
    
        $_ = scalar( reverse $_ );
    }
    
    return $words;
}

sub _S4la {
    #  SYLSYLal -> SYLSYL
    s!^la($syl$syl)!$1!o;
}

sub _S4ec {
    #  SYLSYL[ae]nce -> SYLSYL
    s!^ecn[ae]($syl$syl)!$1!o;
}

sub _S4re {
    #  SYLSYLer -> SYLSYL
    s!^re($syl$syl)!$1!o;
}

sub _S4ci {
    #  SYLSYLic -> SYLSYL
    s!^ci($syl$syl)!$1!o;
}

sub _S4el {
    #  SYLSYL[ai]ble -> SYLSYL
    s!^elb[ai]($syl$syl)!$1!o;
}

sub _S4tn {
    #  SYLSYLant -> SYLSYL, SYLSYLe?ment -> SYLSYL, SYLSYLent -> SYLSYL
    s!^tn(a|e(me?)?)($syl$syl)!$3!o;
}
sub _S4no {
    #  SYLSYL[st]ion -> SYLSYL[st]
    s!^noi([st]$syl$syl)!$1!o;
}

sub _S4uo {
    #  SYLSYLou -> SYLSYL e.g. homologou -> homolog
    s!^uo($syl$syl)!$1!o;
}

sub _S4ms {
    #  SYLSYLism -> SYLSYL
    s!^msi($syl$syl)!$1!o;
}

sub _S4et {
    #  SYLSYLate -> SYLSYL
    s!^eta($syl$syl)!$1!o;
}

sub _S4it {
    #  SYLSYLiti -> SYLSYL
    s!^iti($syl$syl)!$1!o;
}

sub _S4su {
    #  SYLSYLous -> SYLSYL
    s!^suo($syl$syl)!$1!o;
}

sub _S4ev { 
    #  SYLSYLive -> SYLSYL
    s!^evi($syl$syl)!$1!o;
}

sub _S4ez {
    #  SYLSYLize -> SYLSYL
    s!^ezi($syl$syl)!$1!o;
}

sub _S4es {
    #  SYLSYLise -> SYLSYL **
    s!^esi($syl$syl)!$1!o;
}

##############################################################
# Rule set 2

sub _S2lan {
    #  SYLational -> SYLate,	SYLtional -> SYLtion
    s!^lanoita($syl)!eta$1!o || s!^lanoit($syl)!noit$1!o;
}

sub _S2icn {
    #  SYLanci -> SYLance, SYLency ->SYLence
    s!^icn([ae]$syl)!ecn$1!o;
}

sub _S2res {
    #  SYLiser -> SYLise **
    &_S2rez;
}

sub _S2rez {
    #  SYLizer -> SYLize
    s!^re(.)i($syl)!e$1i$2!o;
}

sub _S2ilb {
    #  SYLabli -> SYLable, SYLibli -> SYLible ** (e.g. incredibli)
    s!^ilb([ai]$syl)!elb$1!o;
}

sub _S2ill {
    #  SYLalli -> SYLal
    s!^illa($syl)!la$1!o;
}

sub _S2ilt {
    #  SYLentli -> SYLent
    s!^iltne($syl)!tne$1!o
}

sub _S2ile {
    #  SYLeli -> SYLe
    s!^ile($syl)!e$1!o;
}

sub _S2ils {
    #  SYLousli -> SYLous
    s!^ilsuo($syl)!suo$1!o;
}

sub _S2noi {
    #  SYLization -> SYLize, SYLisation -> SYLise**, SYLation -> SYLate
    s!^noita([sz])i($syl)!e$1i$2!o || s!^noita($syl)!eta$1!o;
}

sub _S2rot {
    #  SYLator -> SYLate
    s!^rota($syl)!eta$1!o;
}

sub _S2msi {
    #  SYLalism -> SYLal
    s!^msila($syl)!la$1!o;
}

sub _S2sse {
    #  SYLiveness  -> SYLive, SYLfulness -> SYLful, SYLousness -> SYLous
    s!^ssen(evi|luf|suo)($syl)!$1$2!o;
}

sub _S2iti {
    #  SYLaliti -> SYLal, SYLiviti -> SYLive, SYLbiliti ->SYLble
    s!^iti(la|lib|vi)($syl)! ( $1 eq 'la' ? 'la' : $1 eq 'lib' ? 'elb' : 'evi' )
	. $2 !eo;
}

##############################################################
# Rule set 3

sub _S3eta {
    #  SYLicate -> SYLic
    s!^etaci($syl)!ci$1!o;
}

sub _S3evi {
    #  SYLative -> SYL
    s!^evita($syl)!$1!o;
}

sub _S3ezi
{
    #  SYLalize -> SYLal
    s!^ezila($syl)!la$1!o;
}

sub _S3esi {
    #  SYLalise -> SYLal **
    s!^esila($syl)!la$1!o;
}

sub _S3iti {
    #  SYLiciti -> SYLic
    s!^itici($syl)!ci$1!o;
}

sub _S3lac {
    #  SYLical -> SYLic
    s!^laci($syl)!ci$1!o;
}
sub _S3luf {
    #  SYLful -> SYL
    s!^luf($syl)!$1!o;
}

sub _S3sse {
    #  SYLness -> SYL
    s!^ssen($syl)!$1!o;
}

1;
