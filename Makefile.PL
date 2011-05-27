use 5.008005;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
my $debug = grep {/^--debug$/} @ARGV;
WriteMakefile(
    NAME              => 'Algorithm::SpatialIndex::Bucket::XS',
    VERSION_FROM      => 'lib/Algorithm/SpatialIndex/Bucket/XS.pm', # finds $VERSION
    PREREQ_PM         => {
      'Algorithm::SpatialIndex'    => '0.06',
    }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Algorithm/SpatialIndex/Bucket/XS.pm', # retrieve abstract from module
       AUTHOR         => 'Steffen Mueller <smueller@cpan.org>') : ()),
    DEFINE            => ($debug ? '-Wall -Wextra -O0' : ''), # e.g., '-DHAVE_SOMETHING'
);
