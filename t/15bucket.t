use strict;
use warnings;
use Algorithm::SpatialIndex::Bucket::XS;

use Test::More;
my $bclass = "Algorithm::SpatialIndex::Bucket::XS";

SCOPE: {
  my $b = $bclass->new(node_id => 13);
  is($b->node_id, 13, "node_id, empty bucket");
  is($b->nitems, 0, "nitems, empty bucket");
}
pass("DESTROY empty bucket");

SCOPE: {
  my $b = $bclass->new(node_id => 12, items => []);
  is($b->node_id, 12, "node_id, empty bucket");
  is($b->nitems, 0, "nitems, empty bucket");
}
pass("DESTROY empty bucket");

SCOPE: {
  my $it = [[1,2,3],[5,6,7],[9,9,9]];
  my $b = $bclass->new(node_id => 1, items => [[1,2,3],[5,6,7],[9,9,9]]);
  is($b->node_id, 1, "node_id, init bucket");
  is($b->nitems, 3, "nitems, init bucket");
  is_deeply(
    $b->items, $it, 'items'
  );
}
pass("DESTROY init bucket");

SCOPE: {
  my $it = [[5,6,7],[9,9,9]];
  my $b = $bclass->new(node_id => 7);
  $b->add_items(@$it);
  is($b->node_id, 7, "node_id, late-init bucket");
  is($b->nitems, 2, "nitems, late-init bucket");
  is_deeply(
    $b->items, $it, 'items'
  );
}
pass("DESTROY late-init bucket");

SCOPE: {
  my $it = [[5,6,7],[9,9,9]];
  my $b = $bclass->new(node_id => 7, items => [[8,7,6]]);
  is($b->nitems, 1, "nitems, reinit bucket");
  $b->add_items(@$it);
  is($b->node_id, 7, "node_id, reinit bucket");
  is($b->nitems, 3, "nitems, reinit bucket");
  is_deeply(
    $b->items, [[8,7,6], @$it], 'items'
  );
  my $eit = [[1000, -12.3, -9999], [90, 1, 1], [0,0,0]];
  $b->add_items(@$eit);
  is($b->nitems, 6, "nitems, reinit bucket");
  is_deeply(
    $b->items, [[8,7,6], @$it, @$eit], 'items'
  );
}
pass("DESTROY late-init bucket");

done_testing;

