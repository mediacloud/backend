package Lingua::EN::Sentence::ApplyRegexWithoutLocale;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;

#use POSIX qw(locale_h);
use utf8;
use Data::Dumper;
use MIME::Base64;
use Encode;

my $output_detailed_debug_info = 0;

sub _apply_dangerous_regex
{
    my ( $text ) = @_;

    if ( $output_detailed_debug_info )
    {
        print "starting _apply_dangerous_regex\n";
        eval {

            #utf8::upgrade( $text );
            print Dumper( $text );
            print "\n";

        };

        my $temp = $text;

        #print Dumper( $temp );
        #utf8::upgrade( $temp );
        my $temp_base64 = encode_base64( encode( "UTF-8", $temp ) );

        eval {
            print "Based64 encoded: '$temp_base64'";
            print "\n";
        };

        utf8::upgrade( $temp_base64 );

        print Dumper ( $temp_base64 );
        print "\n";
    }

    print "starting _apply_dangerous_regex \n";

    $text =~ s/([^-\w]\w[\.!?])\001/$1/sgo;

    # print "starting _apply_dangerous_regex part 1\n";

    # $text =~ s/([^-\w]\w\.)\001/$1/sgo;

    # print "starting _apply_dangerous_regex part 2\n";
    # $text =~ s/([^-\w]\w\!)\001/$1/sgo;
    # print "starting _apply_dangerous_regex part 3\n";
    # $text =~ s/([^-\w]\w\?)\001/$1/sgo;
    # print "Finished _apply_dangerous_regex\n\n";

    return $text;
}

1;
