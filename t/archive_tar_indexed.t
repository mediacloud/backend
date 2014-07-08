use strict;
use warnings;

use File::Temp;
use Test::More tests => 203 + 1;
use Test::NoWarnings;

BEGIN { use_ok 'Archive::Tar::Indexed' }

my $tar_file = File::Temp::tmpnam;

my $files = [];

print STDERR "writing tar file ...\n";

eval {

    for my $i ( 0 .. 100 )
    {
        my $name = "file_$i.txt";
        my $content = ( $i % $$ ) x ( ( $i + 1 ) * $$ );

        my ( $starting_block, $num_blocks ) = Archive::Tar::Indexed::append_file( $tar_file, \$content, $name );

        my $file = {
            name           => $name,
            content        => $content,
            starting_block => $starting_block,
            num_blocks     => $num_blocks
        };

        push( @{ $files }, $file );
    }

    for my $i ( 0 .. 100 )
    {
        my $file = $files->[ $i ];
        my $content_ref =
          Archive::Tar::Indexed::read_file( $tar_file, $file->{ name }, $file->{ starting_block }, $file->{ num_blocks } );

        is( length( ${ $content_ref } ), length( $file->{ content } ), "length of content for file $i" ) || die;
        ok( ${ $content_ref } eq $file->{ content }, "content matches for file $i" ) || die;
    }
};

unlink( $tar_file );

if ( $@ )
{
    die( $@ );
}
