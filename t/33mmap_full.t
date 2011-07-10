use strict;
use warnings;
use Test::More tests => 63*2;
use Algorithm::SpatialIndex;

my $tlibpath;
BEGIN {
  $tlibpath = -d "t" ? "t/lib" : "lib";
}
use lib $tlibpath;

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

Algorithm::SpatialIndex::XSBucketTest->run('MMapBucket', $index2);

#use Data::Dumper; warn Dumper $index;
#use Data::Dumper; warn Dumper $index2;

