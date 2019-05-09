package MediaWords::DBI::Stories::Extract;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

import_python_module( __PACKAGE__, 'extract_and_vector.dbi.stories.extract' );

=head2 get_all_sentences( $db, $story )

Parse sentences in story from the extracted text.  return in the form:

    { sentence => $sentence, ss => $matching_story_sentence, stories_id => $stories_id }

The list of returned sentences includes sentences that are deduped before storing story_sentences for each story. This
function is useful for comparing against the stored story_sentences.

=cut

sub get_all_sentences
{
    my ( $db, $story ) = @_;

    # Tokenize into sentences
    my $lang = MediaWords::Languages::Language::language_for_code( $story->{ language } )
      || MediaWords::Languages::Language::default_language();

    my $text = get_text( $db, $story );
    unless ( defined $text )
    {
        WARN "Text for story " . $story->{ stories_id } . " is undefined.";
        return;
    }
    unless ( length( $text ) )
    {
        WARN "Story " . $story->{ stories_id } . " text is an empty string.";
        return;
    }

    my $raw_sentences = $lang->split_text_to_sentences( $text );
    unless ( defined $raw_sentences )
    {
        die "Sentences for story " . $story->{ stories_id } . " are undefined.";
    }
    unless ( scalar @{ $raw_sentences } )
    {
        WARN "Story " . $story->{ stories_id } . " doesn't have any sentences.";
        return;
    }

    my $all_sentences = [];
    for my $sentence ( @{ $raw_sentences } )
    {
        my $ss = $db->query( <<END, $sentence, $story->{ stories_id } )->hash;
select * from story_sentences where sentence = \$1 and stories_id = \$2
END

        push( @{ $all_sentences }, { sentence => $sentence, ss => $ss, stories_id => $story->{ stories_id } } );
    }

    return $all_sentences;
}

1;
