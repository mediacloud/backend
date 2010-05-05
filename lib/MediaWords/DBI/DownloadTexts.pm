package MediaWords::DBI::DownloadTexts;

# various helper functions for the download_texts table

use strict;

use Encode;
use Perl6::Say;
use Data::Dumper;

use MediaWords::DBI::Downloads;

# extract the text from a download and store that text in download_texts.
# also add the extracted line numbers to extracted_lines
sub create_from_download 
{
    my ( $db, $download ) = @_;
    
    my $extract = MediaWords::DBI::Downloads::extract_download( $db, $download );
    
    $db->query( "delete from download_texts where downloads_id = ?", $download->{downloads_id} );
    
    my $text = $extract->{ extracted_text };
    
    # print "EXTRACT\n**\n$text\n**\n";
    
    my $download_text = $db->create( 'download_texts', { download_text => $text, 
                                                         downloads_id => $download->{downloads_id},
                                                         download_text_length => length($extract->{extracted_text}) });
    
    $db->dbh->do("copy extracted_lines(download_texts_id, line_number) from STDIN");                                             
    for (my $i = 0; $i < @{$extract->{scores}}; $i++) 
    {
        if ($extract->{scores}->[$i]->{is_story}) 
        {
            $db->dbh->pg_putcopydata($download_text->{download_texts_id} . "\t" . $i . "\n");
        }
    }
    
    $db->dbh->pg_putcopyend();
    
    $db->query( "update downloads set extracted = 't' where downloads_id = ?", $download->{downloads_id} );
            
    return $download_text;
}

1;
