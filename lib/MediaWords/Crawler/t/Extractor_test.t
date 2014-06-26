#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use warnings;

use MediaWords::Crawler::Extractor;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More;
use HTML::CruftText 0.02;

Readonly my $test1_input =>

  Readonly my $test1_output =>

  my $test_cases = [
    {
        test_name  => 'empty_comment',
        test_input => <<'__END_TEST_CASE__',
<html>
<header>
</header> <!---->
<body>
Real article text
</body>
<!-- end body -->
</html>
__END_TEST_CASE__
        ,
        test_output => <<'__END_TEST_CASE__',



<body>
Real article text
</body>


__END_TEST_CASE__
    },

    {
        test_name => 'broken_comment',

        test_input => <<'__END_TEST_CASE__',
<html>
<header>
</header> <!--- Foo -->
<body>
Real article text
</body>
<!--- < end body >  --->
</html>
__END_TEST_CASE__
        ,
        test_output =>

          <<'__END_TEST_CASE__',



<body>
Real article text
</body>


__END_TEST_CASE__
    },
    {
        test_name  => 'nested_body',
        test_input => <<'__END_TEST_CASE__',
<html>
<header>
<html>
<body>
JUNK STRING
</body>
</html>
</header>
<body>
Real article text
</body>
</html>
__END_TEST_CASE__
        ,
        test_output => <<'__END_TEST_CASE__',



<body>
JUNK STRING
</body>
</html>
</header>
<body>
Real article text
</body>

__END_TEST_CASE__
    },
    {
        test_name  => '</body> in <script>',
        test_input => <<'__END_TEST_CASE__',
<html>
<header>
</header>
<body>
<script language=javascript type='text/javascript'>
function PrintThisPage() 
{
var sOption='toolbar=yes,location=no,directories=yes,menubar=no,resizable=yes,scrollbars=yes,width=900,height=600,left=100,top=25';
var sWinHTMLa = document.getElementById('divDatesInfo').innerHTML;
try{
var sWinHTMLb = document.getElementById('divContent').innerHTML;
}catch(e){
var sWinHTMLb = document.getElementById('ctl00_divContent').innerHTML;
};
var winprint=window.open('','',sOption);
winprint.document.open();
winprint.document.write('<html><link href=/Styles/PrintAble.css rel=stylesheet type=text/css />');
winprint.document.write('<body><form><Table align=center width=560px>');
winprint.document.write('<tr><td align=Left><img src=/Media/Images/LogoPrint.gif></td><td width=351>&nbsp;</td></tr>');
winprint.document.write('<tr><td align=left width=209>');
winprint.document.write(sWinHTMLa);
winprint.document.write('</td><td width=351>&nbsp;</td></tr><tr><td colspan=2>'); 
winprint.document.write(sWinHTMLb);
winprint.document.write('</td></tr></Table></form></body></html>');
winprint.document.write('<script>window.print()<');
winprint.document.write('/');
winprint.document.write('script>');
winprint.document.close();
winprint.focus();
}
</script>
<p>
ARTICLE TEXT
</p>
</body>
</html>
__END_TEST_CASE__
        ,
        test_output => <<'__END_TEST_CASE__',



<body>
<script language=javascript type='text/javascript'>

























</script>
<p>
ARTICLE TEXT
</p>
</body>

__END_TEST_CASE__
    }
  ];

my $tests = scalar @{ $test_cases } * 2;
plan tests => $tests + 1;

foreach my $test_case ( @{ $test_cases } )
{
    is(
        join( "", map { $_ . "\n" } @{ HTML::CruftText::clearCruftText( $test_case->{ test_input } ) } ),
        $test_case->{ test_output },
        $test_case->{ test_name }
    );

    my $result = MediaWords::Crawler::Extractor::score_lines( HTML::CruftText::clearCruftText( $test_case->{ test_input } ),
        "__NO_TITLE__", "__NO_DESCRIPTION__" );

    ok( $result, "title_not_found_test" );
}
