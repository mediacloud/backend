use Test::Strict;
use Test::NoWarnings;

$Test::Strict::TEST_SKIP = [

	'lib/MediaWords/CommonLibs.pm',

	# Fails with:
	#
	#   Failed test 'Syntax check lib/MediaWords/View/TT.pm'
	#   at /mediacloud/local/lib/perl5/Test/Strict.pm line 394.
	# Mmap of shared file /mediacloud/lib/MediaWords/Util/../../../data/cache/translate/Default.dat failed: Invalid argument at /mediacloud/local/lib/perl5/x86_64-linux-thread-multi/Cache/FastMmap.pm line 640.
	# Compilation failed in require at lib/MediaWords/View/TT.pm line 8.
	# BEGIN failed--compilation aborted at lib/MediaWords/View/TT.pm line 8.
	#
	# Reason seems to be misset "share_file" parameter by the Perl's CHI module.
	'lib/MediaWords/View/TT.pm'

];

all_perl_files_ok( 'lib', 'script' );    # Syntax ok and use strict;
