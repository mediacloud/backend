use strict;
use warnings;

#use Test::More tests => 6;
use Test::More skip_all => "Need to find a way to test the storyvector stuff";

BEGIN
{
    use_ok( 'MediaWords::Pg::StoryVectors' );

    #use_ok('MediaWords::Pg::Schema');
}

require_ok( 'MediaWords::Pg::StoryVectors' );

#require_ok('MediaWords::Pg::Schema');

#use MediaWords::Pg::Schema;
my $_spi_functions = [
    qw/spi_exec_query spi_query spi_fetchrow spi_prepare spi_exec_prepared
      spi_query_prepared spi_cursor_close spi_freeplan elog/
];

#foreach my $spi_function ($_spi_functions)
#{
#	 MediaWords::Pg::set_spi('$spi_function', \&$spi_function);
#}

MediaWords::Pg::StoryVectors::_fake_update_story_sentence_words( '5', 1 );

print STDERR "finished testing\n";
