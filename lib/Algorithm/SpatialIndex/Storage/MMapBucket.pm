package Algorithm::SpatialIndex::Storage::MMapBucket;

use strict;
use warnings;

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
        my $dir = $opt->{path};

        for my $tuple (
            [BUCKETS_FILE, \$self->{buckets}],
        ) {
            #my ($filetemplate, $ref) = @$tuple;
            #my $file = sprintf $filetemplate, $dir;
            #map_file(my $map, $file, '<') or die "Could not map $file";
            #$$ref = \$map;
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
