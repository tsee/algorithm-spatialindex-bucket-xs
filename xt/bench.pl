package Algorithm::SpatialIndex::XSBucketTest;
use strict;
use warnings;
use Test::More;
use Algorithm::SpatialIndex;
use Algorithm::SpatialIndex::Strategy::QuadTree;
use Time::HiRes qw(sleep time);
use lib 't/lib';
use Algorithm::SpatialIndex::XSBucketTest;


mkdir 'tmpdir';
my $tmpdir = 'tmpdir';
use Algorithm::SpatialIndex::XSBucketTest;
my $index = Algorithm::SpatialIndex::XSBucketTest->run('MMapBucket', path => $tmpdir);
$index->storage->write_to_disk;


my $index2 = Algorithm::SpatialIndex->new(
  bucket_class => 'Algorithm::SpatialIndex::Bucket::XS',
  strategy => 'QuadTree',
  storage  => 'MMapBucket',
  limit_x_low => $index->limit_x_low,
  limit_y_low => $index->limit_y_low,
  limit_x_up  => $index->limit_x_up,
  limit_y_up  => $index->limit_y_up,
  bucket_size => $index->bucket_size,
  path => $tmpdir,
  load_mmap => 1,
);

# WARNING
# This makes the bench below work -- that means the whole mmapping has been broken and I am a muppet. Doh.
Algorithm::SpatialIndex::XSBucketTest->run('MMapBucket', $index2);

test_fetches($index, 'Original index');
test_fetches($index2, 'Mmap index');

sub test_fetches {
  my $idx = shift;
  my $name = shift;
  my $time = time;
  my $n = 5000;
  for my $i (1..$n) {
    my @items = $idx->get_items_in_rect(qw( 13 0 13.2 0.2 ));
    warn scalar(@items) if $i == 1;
  }
  printf "$name: Each get took: %.3f ms\n", (time()-$time)/$n*1000;
}

done_testing;

