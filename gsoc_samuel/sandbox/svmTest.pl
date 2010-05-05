#!/usr/bin/perl

use Algorithm::SVM;
use Algorithm::SVM::DataSet;



my $svm = new Algorithm::SVM(Type   => 'C-SVC',
                            Kernel => 'radial',
                            Gamma  => 64,
                            C      => 8);

$svm->load('news-ku.model');
$num = $svm->getNRClass();;
print $num;
my $ds1 = new Algorithm::SVM::DataSet(Label => 1);

my @d1 = (0.8,0.630278,1,0.7241622,0.2280135);

$ds1->attribute(1, $d1[0]);
$ds1->attribute(2, $d1[1]);
$ds1->attribute(3, $d1[2]);
$ds1->attribute(4, $d1[3]);
$ds1->attribute(5, $d1[4]);

print $svm->predict($ds1);
