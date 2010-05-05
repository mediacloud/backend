#!/usr/bin/perl

# call plperl function to update story vectors

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;

use MediaWords::DB;

sub main
{
    my $db = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);

    $db->query("select update_wordcloud_story_vectors()");
}

main();
