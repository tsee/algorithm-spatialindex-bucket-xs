package Algorithm::SpatialIndex::Storage::MMapBucket;

use strict;
use warnings;

# WARNING WARNING WARNING
# This whole implementation is a disgrace and needs proper
# reimplementation. :)
# WARNING WARNING WARNING


use Carp qw(croak);

use parent 'Algorithm::SpatialIndex::Storage::Memory';

use Data::Dumper;
use JSON::XS ();

use constant {
  BUCKETS_FILE => '%s/buckets.mmap',
  BUCKETS_INDEX_FILE => '%s/buckets_index.json',
};

sub init {
  my $self = shift;
  $self->SUPER::init(@_);

  my $opt = $self->{opt};
  if (not defined $opt->{path}) {
    croak("Algorithm::SpatialIndex::Storage::MMapBucket requires a path parameter");
  }

  if ($opt->{load_mmap}) {
    # TODO this is all nice and well for buckets. Or so I assume, but I can't know
    # because this was never tested -- I can only dump (XS) buckets to disk at this point,
    # not the rest of the tree, particularly not the nodes. Asks for A::SI::Node::XS. *sigh*
    my $dir = $opt->{path};
    my $b_file = sprintf(BUCKETS_FILE(), $dir);
    my $b_index_file = sprintf(BUCKETS_INDEX_FILE(), $dir);
    croak("Can't locate buckets index file '$b_index_file'") if not -f $b_index_file;
    croak("Can't locate buckets dump file '$b_file'") if not -f $b_file;
    my $index = JSON::XS::decode_json(do {local $/; open my $fh, "<", $b_index_file or die $!; <$fh>});

    my $bucks = Algorithm::SpatialIndex::Bucket::XS->_new_buckets_from_mmap_file(
      $b_file,
      (-s $b_file),
      $index
    );

    # FIXME this is inelegant as hell
    my $b_storage = $self->{buckets};
    foreach my $bucket (@$bucks) {
      $b_storage->[$bucket->node_id] = $bucket;
    }
  }
}

sub write_buckets_to_disk {
  my $self = shift;

  my $dir = $self->{opt}{path};
  open my $buckets_fh, '>', sprintf(BUCKETS_FILE, $dir)
      or die "Failed to open buckets file for writing: $!";
  binmode $buckets_fh;

  my $buckets_index = [];

  for my $node (@{ $self->{nodes} }) {
    my $bucket = $self->{buckets}->[$node->id];
    if (defined($bucket)) {
      # HACK!
      push @$buckets_index, [$node->id, tell($buckets_fh)];
      print $buckets_fh $bucket->dump_as_string();
    }
  }

  open my $bidx_fh, '>', sprintf(BUCKETS_INDEX_FILE, $dir)
    or die "Failed to open buckets index file for writing: $!";
  print $bidx_fh JSON::XS::encode_json($buckets_index);
  close $bidx_fh;

  return $buckets_index;
}


1;
