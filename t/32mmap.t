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
my $nbuckets = $index->storage->write_buckets_to_disk;
warn "# Expect $nbuckets buckets\n";

my $f = "tmpdir/buckets.mmap";
my @bucks = Algorithm::SpatialIndex::Bucket::XS->_new_buckets_from_mmap_file(
  $f,
  (-s $f),
  $nbuckets
);
warn scalar(@bucks);

warn $bucks[0];

