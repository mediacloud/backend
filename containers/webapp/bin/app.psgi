use strict;
use warnings;

use MediaWords;

my $app = MediaWords->apply_default_middlewares(MediaWords->psgi_app);
$app;

