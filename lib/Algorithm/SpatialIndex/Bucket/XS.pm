package Algorithm::SpatialIndex::Bucket::XS;
use 5.008005;
use strict;
use warnings;
use Carp qw(croak);

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Algorithm::SpatialIndex::Bucket::XS', $VERSION);

sub isa {
  my $class_or_self = shift;
  my $check_class = shift;
  # FIXME this is probbaly entirely broken...
  return $class_or_self->SUPER::isa($check_class) || $check_class eq 'Algorithm::SpatialIndex::Bucket';
}

sub new {
  my $class = shift;
  my %opt = @_;
  return $class->_new_bucket($opt{node_id}, $opt{items}||[]);
}

1;
__END__

=head1 NAME

Algorithm::SpatialIndex::Bucket::XS - A bucket implementation in XS

=head1 SYNOPSIS

  use Algorithm::SpatialIndex;
  my $idx = Algorithm::SpatialIndex->new(
    bucket_class => 'Algorithm::SpatialIndex::Bucket::XS',
    #...
  );

=head1 DESCRIPTION

...

Likely not thread-safe.

=head1 SEE ALSO

L<Algorithm::SpatialIndex>

L<Algorithm::SpatialIndex::Bucket::XS>

=head1 AUTHOR

Steffen Mueller, E<lt>smueller@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2011 by Steffen Mueller

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=cut
