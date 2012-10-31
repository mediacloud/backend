#!/usr/bin/env perl
#
# Language detection module evaluation script.
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::DB;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

# Candidate 1 -- Lingua::Identify
# http://search.cpan.org/~ambs/Lingua-Identify-0.51/lib/Lingua/Identify.pm
use Lingua::Identify;

# Candidate 2 -- Lingua::Ident
# http://search.cpan.org/~mpiotr/Lingua-Ident-1.7/Ident.pm
use Lingua::Ident;

# Candidate 3 -- TextCat
# http://odur.let.rug.nl/vannoord/TextCat/
# http://spamassassin.apache.org/
use Mail::SpamAssassin::Plugin::TextCat;

# Candidate 4 -- Compact Language Detector (C++)
# http://code.google.com/p/chromium-compact-language-detector/
# http://www.swig.org/
use CLD;

# Candidate 5 -- LingPipe (Java)
# http://alias-i.com/lingpipe/demos/tutorial/langid/read-me.html
use Inline::Java;

# Candidate 6 -- NLTK (Python)
# http://borel.slu.edu/crubadan/apps.html
# https://code.google.com/p/nltk/
use Inline::Python;

