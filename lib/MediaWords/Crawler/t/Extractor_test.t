#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;
use MediaWords::Crawler::Extractor;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Readonly;

use Test::NoWarnings;
use Test::More;
use MediaWords::Util::HTML;

Readonly my $test1_input =>

  Readonly my $test1_output =>

  # Notes:
  # * It's legal to leave "<header>" (not "<head>") element inact because it's
  # one of HTML5 elements
  my $test_cases = [

    # Simple basic XHTML page
    {
        test_name  => 'basic_html_page',
        test_input => <<__END_TEST_CASE__,


<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<html xmlns="http://www.w3.org/1999/xhtml" lang="en" xml:lang="en">

<head>
    <title>This is a test</title>
    <meta http-equiv="content-type" content="text/html; charset=utf-8" />
    <style type="text/css" media="all"><!--

    body {
        font-family: Verdana, sans-serif;
    }

    --></style>

</head>

<body>

<h1>This is a test</h1>

<p>Hello! This is a test HTML page.</p>

<ul>
    <li>First item.</li>
    <li>Second item.</li>
</ul>

</body>

</html>

__END_TEST_CASE__
        test_output => <<__END_TEST_CASE__,
<body>

<h1>This is a test</h1>

<p>Hello! This is a test HTML page.</p>

<ul>
    <li>First item.</li>
    <li>Second item.</li>
</ul>

</body>
__END_TEST_CASE__
    },

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
<body><header>
</header> 

Real article text

<!-- end body -->
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
        test_output => <<'__END_TEST_CASE__',
<body><header>
</header> <!--- Foo -->

Real article text

<!--- | end body |  --->
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
JUNK STRING<br />
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
<body><header>


JUNK STRING<br/>


</header>

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
<body><header>
</header>

<script language="javascript" type="text/javascript"> </script>
<p>
ARTICLE TEXT
</p>

</body>
__END_TEST_CASE__
    },
    {
        test_name  => 'wrapped_html_tag',
        test_input => <<__END_TEST_CASE__,
FOO<a 
   href="bar.com">BAZ
__END_TEST_CASE__
        test_output => <<__END_TEST_CASE__,
<body>
  <p>FOO<a href="bar.com">BAZ
</a></p>
</body>
__END_TEST_CASE__
    }
  ];

my $tests = scalar @{ $test_cases } * 2;
plan tests => $tests + 1;

foreach my $test_case ( @{ $test_cases } )
{
    my $clean_html = MediaWords::Util::HTML::clear_cruft_text( $test_case->{ test_input } );

    is( $clean_html, $test_case->{ test_output }, $test_case->{ test_name } );

    my $result = MediaWords::Crawler::Extractor::score_lines( [ split( /[\n\r]+/, $clean_html ) ],
        "__NO_TITLE__", "__NO_DESCRIPTION__" );

    ok( $result, "title_not_found_test" );
}
