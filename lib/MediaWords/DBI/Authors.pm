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

sub _find_first_node
{
    ( my $tree, my $xpath ) = @_;

    my @nodes = $tree->findnodes( $xpath );

    my $node = pop @nodes;

    return $node;
}

sub _get_by_line_from_content
{
    ( my $content ) = @_;

    if ( ref $content )
    {
        $content = $$content;
    }

    #say "dl content:${$content}";

    my $tree = HTML::TreeBuilder::XPath->new;    # empty tree
    $tree->parse_content( $content );

    my $node = _find_first_node( $tree, '//meta[@name="byl"]' );

    my $ret;

    if ( $node )
    {
        my $content_attr = $node->attr( 'content' );
        $ret = $content_attr;
    }
    elsif ( $node = _find_first_node( $tree, '//meta[@name="CLMST"]' ) )
    {
        my $content_attr = $node->attr( 'content' );
        $ret = $content_attr;
    }
    elsif ( $node = _find_first_node( $tree, '//address[@class="byline author vcard"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//p[@class="byline author vcard"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//p[@class="author vcard"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//meta[@name="byline"]' ) )
    {
        my $content_attr = $node->attr( 'content' );
        $ret = $content_attr;
    }
    elsif ( $node = _find_first_node( $tree, '//meta[@name="AUTHOR"]' ) )
    {
        my $content_attr = $node->attr( 'content' );
        $ret = $content_attr;
    }
    elsif ( $node = _find_first_node( $tree, '//meta[@name="author"]' ) )
    {
        my $content_attr = $node->attr( 'content' );
        $ret = $content_attr;
    }
    elsif ( $node = _find_first_node( $tree, '//span[@class="byline-name"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//span[@class="author"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//a[@class="author"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//a[@class="contributor"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//meta[@name="DCSext.author"]' ) )
    {
        my $content_attr = $node->attr( 'content' );
        $ret = $content_attr;
    }
    elsif ( $node = _find_first_node( $tree, '//meta[@name="Search.Author" and @property="og:author"]' ) )
    {
        my $content_attr = $node->attr( 'content' );
        $ret = $content_attr;
    }
    elsif ( $node = _find_first_node( $tree, '//meta[@name="Search.Byline"]' ) )
    {
        my $content_attr = $node->attr( 'content' );
        $ret = $content_attr;
    }
    elsif ( $node = _find_first_node( $tree, '//h3[@property="foaf:name"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//h3[@class="byline"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//p[@class="byline"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//span[@id="byline"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//a[@id="emailWriter"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//div[@class="byline"]/span[@class="name"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//div[@id="byline"]/a' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//div[@class="byLine" and @id="byLineTag"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//a[@class="personality"]' ) )
    {
        $ret = $node->as_text;
    }
    elsif ( $node = _find_first_node( $tree, '//div[@id="byline"]' ) )
    {
        $ret = $node->as_text;
    }
     else
    {
        say STDERR "author not found";
    }

    $tree->delete;

    return $ret;
}

sub get_author_from_content
{
    ( my $content ) = @_;

    my $by_line = _get_by_line_from_content( $content );

    my $author;

    if ( $by_line )
    {
        $author = $by_line;

        $author =~ s/^By //i;
        $author = lc( $author );
	$author =~ s/^posted by\:? //;
	$author =~ s/^\s*//;
	$author =~ s/\s*$//;
	$author =~ s/\s+/ /;
	$author =~ s/posted by\:? //;
    }

    return $author;
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
