#!/usr/bin/env perl
#
# Test text similarity scoring
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

use Time::HiRes;
use MediaWords::Util::Text;
use Text::Similarity::Overlaps;

use constant TEST_ITERATIONS => 1000;

sub main
{
    my $text_description = <<EOF;
One morning, when Gregor Samsa woke from troubled dreams, he found himself
transformed in his bed into a horrible vermin. He lay on his armour-like back,
and if he lifted his head a little he could see his brown belly, slightly domed
and divided by arches into stiff sections. The bedding was hardly able to cover
it and seemed ready to slide off any moment. His many legs, pitifully thin
compared with the size of the rest of him, waved about helplessly as he looked.
EOF

    my $text_body = <<EOF;
One morning, when Gregor Samsa woke from troubled dreams, he found himself
transformed in his bed into a horrible vermin. He lay on his armour-like back,
and if he lifted his head a little he could see his brown belly, slightly domed
and divided by arches into stiff sections. The bedding was hardly able to cover
it and seemed ready to slide off any moment. His many legs, pitifully thin
compared with the size of the rest of him, waved about helplessly as he looked.

"What's happened to me?" he thought. It wasn't a dream. His room, a proper
human room although a little too small, lay peacefully between its four
familiar walls. A collection of textile samples lay spread out on the table -
Samsa was a travelling salesman - and above it there hung a picture that he had
recently cut out of an illustrated magazine and housed in a nice, gilded frame.
It showed a lady fitted out with a fur hat and fur boa who sat upright, raising
a heavy fur muff that covered the whole of her lower arm towards the viewer.
EOF

    my $x;
    my $score;

    my $time_before = Time::HiRes::time();
    for ( $x = 0 ; $x < TEST_ITERATIONS ; ++$x )
    {
        # Change the second text parameter a bit so that this manual test
        # better emulates how it's being used in the real world (first
        # parameter is usually a constant "title + description" and the second
        # one is a line from the text)
        $text_body .= ' ';
        $score = MediaWords::Util::Text::get_similarity_score( $text_description, $text_body, 'en' );
    }
    my $time_after = Time::HiRes::time();

    print "MediaWords::Util::Text::get_similarity_score() score: $score\n";
    printf "Time: %2.6f\n\n", ( $time_after - $time_before );

    $time_before = Time::HiRes::time();
    my $sim = Text::Similarity::Overlaps->new( { normalize => 1, verbose => 0 } );
    for ( $x = 0 ; $x < TEST_ITERATIONS ; ++$x )
    {
        $text_body .= ' ';
        $score = $sim->getSimilarityStrings( $text_description, $text_body );
    }
    $time_after = Time::HiRes::time();

    print "Text::Similarity::Overlaps() score: $score\n";
    printf "Time: %2.6f\n", ( $time_after - $time_before );
}

main();
