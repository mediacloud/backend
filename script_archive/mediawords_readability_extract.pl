#!/usr/bin/env perl

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Getopt::Long;

use MediaWords::CommonLibs;

use MediaWords::Thrift::Extractor;
use MediaWords::Util::ThriftExtractor;

use File::Slurp;

use Encode qw(decode encode encode_utf8);
use utf8;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );
    $| = 1;

    my $file_name;

    Getopt::Long::GetOptions( "file=s" => \$file_name ) || return;

    die( "Usage: $0 --file < html file >" ) unless ( $file_name );

    #my $raw_html = "<html><title>article title</title><body><p>paragraph 1</p></body>";

    my $raw_html = read_file( $file_name );    #, binmode => ':utf8' ) ;

    utf8::upgrade( $raw_html );

    my $result = MediaWords::Util::ThriftExtractor::get_extracted_html( $raw_html );

    #MediaWords::Thrift::Extractor::extract_html( $raw_html );

    say Dumper( $result );

    #my $res =  $result->[1];

    #utf8::upgrade( $res );

    #say ($res);

    #say utf8::encode( $res );

    #say 'he’ll ';

}

main();

__END__
