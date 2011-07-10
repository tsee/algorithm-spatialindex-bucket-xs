use strict;
use warnings;
use Test::More tests => 63;
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
my $buck_index = $index->storage->_write_buckets_to_disk;
print "# Expect ".scalar(@$buck_index)." buckets\n";

my $bf = "tmpdir/buckets.mmap";
my $bucks = Algorithm::SpatialIndex::Bucket::XS->_new_buckets_from_mmap_file(
  $bf,
  (-s $bf),
  #$buck_idx
  $buck_index
);

