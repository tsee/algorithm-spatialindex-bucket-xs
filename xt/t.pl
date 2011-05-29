package Algorithm::SpatialIndex::XSBucketTest;
use strict;
use warnings;
use Test::More;
use Algorithm::SpatialIndex::Bucket::XS;
use Data::Dumper;
$|=1;
SCOPE: {
  my $b =Algorithm::SpatialIndex::Bucket::XS->new(
    items => [
      [17,5,5],
    ],
    node_id => 123,
  );
  $b->dump;
  $b->add_items([1,2,3], [2,3,4], [9,9,9]);
  $b->dump;

  #$b->items();
  #$b->dump;

  $b->add_items([3..5], [4..6]);
  $b->dump;
  $b->add_items([5..7]);

  warn Dumper $b->items;
}

my $b =Algorithm::SpatialIndex::Bucket::XS->new(
  items => [
  ],
  node_id => 123,
);


$b->items();

$b->add_items();

$b->add_items([5,1,2], [6,3,4]);

$b->items();
warn "alive";
my $clone = $b->invariant_clone;
$clone->dump;
warn "alive2";
warn $clone->nitems;
warn Dumper $clone->items;
exit;
