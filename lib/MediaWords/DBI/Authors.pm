package MediaWords::DBI::Authors;

use strict;

use Encode;
use Perl6::Say;
use Data::Dumper;
use MediaWords::DBI::Downloads;
use MediaWords::DBI::Stories;
use Data::Dumper;
use Encode;
use MIME::Base64;
use Perl6::Say;
use HTML::TreeBuilder;
use HTML::TreeBuilder::XPath;

use MediaWords::DBI::Downloads;

sub get_author_from_content
{
    ( my $content ) = @_;

    if ( ref $content )
    {
        $content = $$content;
    }

    #say "dl content:${$content}";

    my $tree = HTML::TreeBuilder::XPath->new;    # empty tree
    $tree->parse_content( $content );

    my @nodes = $tree->findnodes( '//meta[@name="byl"]' );

    my $node = pop @nodes;

    if ( $node )
    {
        my $content_attr = $node->attr( 'content' );
        return $content_attr;
    }
    else
    {

        @nodes = $tree->findnodes( '//address[@class="byline author vcard"]' );

        $node = pop @nodes;

        if ( !$node )
        {
            return;
        }

        return $node->as_text;
    }
}

sub create_from_download
{
    my ( $db, $download ) = @_;

    # my $extract = MediaWords::DBI::Downloads::extract_download( $db, $download );

    # $db->query( "delete from download_texts where downloads_id = ?", $download->{ downloads_id } );

    # my $text = $extract->{ extracted_text };

    # # print "EXTRACT\n**\n$text\n**\n";

    # my $download_text = $db->create(
    #     'download_texts',
    #     {
    #         download_text        => $text,
    #         downloads_id         => $download->{ downloads_id },
    #         download_text_length => length( $extract->{ extracted_text } )
    #     }
    # );

    # $db->dbh->do( "copy extracted_lines(download_texts_id, line_number) from STDIN" );
    # for ( my $i = 0 ; $i < @{ $extract->{ scores } } ; $i++ )
    # {
    #     if ( $extract->{ scores }->[ $i ]->{ is_story } )
    #     {
    #         $db->dbh->pg_putcopydata( $download_text->{ download_texts_id } . "\t" . $i . "\n" );
    #     }
    # }

    # $db->dbh->pg_putcopyend();

    # $db->query( "update downloads set extracted = 't' where downloads_id = ?", $download->{ downloads_id } );

    # return $download_text
}

1;
