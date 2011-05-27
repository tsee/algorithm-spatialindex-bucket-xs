package Algorithm::SpatialIndex::XSBucketTest;
use strict;
use warnings;
use Test::More;
use Algorithm::SpatialIndex;
use Algorithm::SpatialIndex::Strategy::QuadTree;

my @limits = qw(12 -2 15 7);
my $index = Algorithm::SpatialIndex->new(
  bucket_class => $ENV{PERL_ASI_BUCKET_CLASS}||'Algorithm::SpatialIndex::Bucket::XS',
  strategy => 'QuadTree',
  storage  => 'Memory',
  limit_x_low => $limits[0],
  limit_y_low => $limits[1],
  limit_x_up  => $limits[2],
  limit_y_up  => $limits[3],
  bucket_size => 2000,
);

isa_ok($index, 'Algorithm::SpatialIndex');

my $strategy = $index->strategy;
isa_ok($strategy, 'Algorithm::SpatialIndex::Strategy::QuadTree');

is($strategy->no_of_subnodes, 4, 'QuadTree has four subnodes');
is_deeply([$strategy->coord_types], [qw(double double double double double double)], 'QuadTree has six coordinates');

my $scale = 70;
my $item_id = 0;
foreach my $x (map {$_/$scale} $limits[0]*$scale..$limits[2]*$scale) {
  foreach my $y (map {$_/$scale} $limits[1]*$scale..$limits[3]*$scale) {
    $index->insert($item_id++, $x, $y);
  }
}

diag("Inserted $item_id nodes");

use Time::HiRes qw(sleep time);
my $time = time;
for my $i (1..500) {
  my @items = $index->get_items_in_rect(qw( 13 0 13.1 0.1 ));
  warn scalar(@items) if $i == 1;
}
printf "Took: %.3f\n", time()-$time;

