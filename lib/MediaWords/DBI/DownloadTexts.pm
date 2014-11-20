package MediaWords::DBI::DownloadTexts;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various helper functions for the download_texts table

use strict;

use Encode;

use Data::Dumper;

use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::DBI::Downloads;
use Try::Tiny;

#use Regexp::Optimizer;

my $_block_level_element_tags = [
    qw ( h1 h2 h3 h4 h5 h6 p div dl dt dd ol ul li dir menu
      address blockquote center div hr ins noscript pre )
];

my $tag_list = join '|', ( map { quotemeta $_ } ( @{ $_block_level_element_tags } ) );

my $_block_level_start_tag_re = qr{
                   < (:? $tag_list ) (:? > | \s )
           }ix
  ;

my $_block_level_end_tag_re = qr{
                   </ (:? $tag_list ) >
           }ix
  ;

sub _contains_block_level_tags
{
    my ( $string ) = @_;

    if ( $string =~ $_block_level_start_tag_re )
    {
        return 1;
    }

    if ( $string =~ $_block_level_end_tag_re )
    {
        return 1;
    }

    return 0;
}

sub _new_lines_around_block_level_tags
{
    my ( $string ) = @_;

    #say STDERR "_new_lines_around_block_level_tags '$string'";

    return $string if ( !_contains_block_level_tags( $string ) );

    $string =~ s{
       ( $_block_level_start_tag_re
      )
      }
      {\n\n$1}gsxi;

    $string =~ s{
       (
$_block_level_end_tag_re
     )
     }
     {$1\n\n}gsxi;

    #say STDERR "_new_lines_around_block_level_tags '$string'";

    #exit;

    #$string = 'sddd';

    return $string;

}

sub _get_extracted_html
{
    my ( $lines, $included_lines ) = @_;

    my $is_line_included = { map { $_ => 1 } @{ $included_lines } };

    my $config = MediaWords::Util::Config::get_config;
    my $dont_add_double_new_line_for_block_elements =
      defined( $config->{ mediawords }->{ disable_block_element_sentence_splitting } )
      && ( $config->{ mediawords }->{ disable_block_element_sentence_splitting } eq 'yes' );

    my $extracted_html = '';

    # This variable is used to make sure we don't add unnecessary double newlines
    my $previous_concated_line_was_story = 0;

    for ( my $i = 0 ; $i < @{ $lines } ; $i++ )
    {
        if ( $is_line_included->{ $i } )
        {
            my $line_text;

            $previous_concated_line_was_story = 1;

            unless ( $dont_add_double_new_line_for_block_elements )
            {

                $line_text = _new_lines_around_block_level_tags( $lines->[ $i ] );
            }
            else
            {
                $line_text = $lines->[ $i ];
            }

            $extracted_html .= ' ' . $line_text;
        }
        elsif ( _contains_block_level_tags( $lines->[ $i ] ) )
        {

            unless ( $dont_add_double_new_line_for_block_elements )
            {
                ## '\n\n\ is used as a sentence splitter so no need to add it more than once between text lines
                if ( $previous_concated_line_was_story )
                {

                    # Add double newline bc/ it will be recognized by the sentence splitter as a sentence boundary.
                    $extracted_html .= "\n\n";

                    $previous_concated_line_was_story = 0;
                }
            }
        }
    }

    return $extracted_html;
}

sub update_extractor_results_with_text_and_html
{
    my ( $extractor_results ) = @_;

    my $download_lines = $extractor_results->{ download_lines };

    my $included_line_numbers = $extractor_results->{ included_line_numbers };
    my $extracted_html = _get_extracted_html( $download_lines, $included_line_numbers );

    my $extracted_text = html_strip( $extracted_html );

    $extractor_results->{ extracted_html } = $extracted_html;
    $extractor_results->{ extracted_text } = $extracted_text;

    return $extractor_results;
}

# get the extracted html from the database for the given download
sub _get_extracted_html_from_db
{
    my ( $db, $download_text ) = @_;

    my $extracted_line_numbers =
      $db->query( "SELECT line_number from extracted_lines where download_texts_id = ? order by line_number asc",
        $download_text->{ download_texts_id } )->flat;

    my $download = $db->query( 'SELECT * from downloads where downloads_id = ? ', $download_text->{ downloads_id } )->hash;

    my $lines = MediaWords::DBI::Downloads::fetch_preprocessed_content_lines( $db, $download );

    return _get_extracted_html( $lines, $extracted_line_numbers );
}

# extract the text from a download and store that text in download_texts.
# also add the extracted line numbers to extracted_lines
sub create_from_download
{
    my ( $db, $download ) = @_;

    my $extract = MediaWords::DBI::Downloads::extractor_results_for_download( $db, $download );

    # say STDERR Dumper( $extract );

    my $included_line_numbers = $extract->{ included_line_numbers };

    $db->query( "delete from download_texts where downloads_id = ?", $download->{ downloads_id } );

    my $download_lines = $extract->{ download_lines };

    my $extracted_html = _get_extracted_html( $download_lines, $included_line_numbers );

    my $extracted_text = html_strip( $extracted_html );

    # say STDERR "EXTRACT\n**\n$extracted_text\n**\n";

    my $download_text = $db->query( <<END, $extracted_text, $download->{ downloads_id } )->hash;
insert into download_texts ( download_text, downloads_id, download_text_length )
    values ( \$1, \$2, char_length( \$1 ) )
    returning *
END

    $db->dbh->do( "copy extracted_lines(download_texts_id, line_number) from STDIN" );
    foreach my $included_line_number ( @{ $included_line_numbers } )
    {

        $db->dbh->pg_putcopydata( $download_text->{ download_texts_id } . "\t" . $included_line_number . "\n" );
    }

    $db->dbh->pg_putcopyend();

    $db->query( "update downloads set extracted = 't' where downloads_id = ?", $download->{ downloads_id } );

#die "Extractor text length mismatch for $download_text->{ download_texts_id } :    " . length($extracted_text) . " != " . length($download_text->{download_text }) unless length($extracted_text) eq length($download_text->{download_text });

#    die "Extractor text mismatch for $download_text->{ download_texts_id } " unless $extracted_text eq $download_text->{download_text };

    return $download_text;
}

1;
