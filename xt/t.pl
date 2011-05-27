package Algorithm::SpatialIndex::XSBucketTest;
use strict;
use warnings;
use Test::More;
use Algorithm::SpatialIndex::Bucket::XS;

my $b =Algorithm::SpatialIndex::Bucket::XS->new(
  items => [
  [1,1,1],
  [2,3,4],
  [3,1,1],
  [4,1,1],
  ],
  node_id => 123,
);

$b->items();

$b->add_items();

$b->add_items([5,1,1], [6,1,1]);
$b->add_items([5,1,1], [6,1,1]);
$b->add_items([5,1,1], [6,1,1]);
$b->add_items([5,1,1], [6,1,1]);
$b->add_items([5,1,1], [6,1,1]);
$b->add_items([5,1,1], [6,1,1]);

$b->items();
