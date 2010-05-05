use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib", "$FindBin::Bin/lib";

}

use warnings;
use Data::Dumper;
use Test::More skip_all => 'We are moving away from using CLUTO';

use Statistics::Cluto ':all' ;



   
   my $c = new Statistics::Cluto;
   
   $c->set_dense_matrix(4, 5, [
     [8, 8, 0, 3, 2],
     [2, 9, 9, 1, 4],
     [7, 6, 1, 2, 3],
     [1, 7, 8, 2, 1]
   ]);

   $c->set_options({
     rowlabels => [ 'row0', 'row1', 'row2', 'row3' ],
     collabels => [ 'col0', 'col1', 'col2', 'col3', 'col4' ],
     nclusters => 2,
     rowmodel => CLUTO_ROWMODEL_NONE,
     colmodel => CLUTO_COLMODEL_NONE,
     pretty_format => 1,
   });
   
   my $clusters = $c->VP_ClusterRB;
   print Dumper $clusters;
   
   my $cluster_features = $c->V_GetClusterFeatures;
   print Dumper $cluster_features;
