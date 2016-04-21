use strict;
use warnings;
use utf8;

use Test::More tests => 10;
use Test::NoWarnings;

use Text::Trim;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Util::HTML' );
}

sub test_html_strip()
{
    my $input_html = <<EOF;
        <strong>Hello!</strong>
EOF
    my $expected_output = 'Hello!';
    my $actual_output   = trim( MediaWords::Util::HTML::html_strip( $input_html ) );
    is( $actual_output, $expected_output, 'html_strip()' );
}

sub test_html_title()
{
    {
        my $input_html = <<EOF;
            <title>This is the title</title>
EOF
        my $fallback        = undef;
        my $expected_output = 'This is the title';
        my $actual_output   = MediaWords::Util::HTML::html_title( $input_html, $fallback );
        is( $actual_output, $expected_output, 'html_title() - basic test' )
    }

    {
        my $input_html      = '';
        my $fallback        = undef;
        my $expected_output = undef;
        my $actual_output   = MediaWords::Util::HTML::html_title( $input_html, $fallback );
        is( $actual_output, $expected_output, 'html_title() - empty' )
    }

    {
        my $input_html = undef;
        my $fallback   = undef;
        eval { MediaWords::Util::HTML::html_title( $input_html, $fallback ); };
        ok( $@, 'html_title() - undef' );
    }

    {
        my $input_html = <<EOF;
            No title to be found here.
EOF
        my $fallback        = 'Fallback title (e.g. an URL)';
        my $expected_output = $fallback;
        my $actual_output   = MediaWords::Util::HTML::html_title( $input_html, $fallback );
        is( $actual_output, $expected_output, 'html_title() - fallback' )
    }

    {
        my $input_html = <<EOF;
            <title>Title with <br /> HTML <strong>tags</strong></title>
EOF
        my $fallback        = undef;
        my $expected_output = 'Title with HTML tags';
        my $actual_output   = MediaWords::Util::HTML::html_title( $input_html, $fallback );
        is( $actual_output, $expected_output, 'html_title() - strip HTML' )
    }

    {
        my $input_html = <<EOF;
            <title>Very very very very very long title</title>
EOF
        my $fallback        = undef;
        my $expected_output = 'Very';
        my $actual_output   = MediaWords::Util::HTML::html_title( $input_html, $fallback, 4 );
        is( $actual_output, $expected_output, 'html_title() - trimmed title' )
    }

    {
        my $input_html = <<EOF;
            <title>...........home Title</title>
EOF
        my $fallback        = undef;
        my $expected_output = 'Title';
        my $actual_output   = MediaWords::Util::HTML::html_title( $input_html, $fallback );
        is( $actual_output, $expected_output, 'html_title() - _get_medium_title_from_response() exception' )
    }
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_html_strip();
    test_html_title();
}

main();
