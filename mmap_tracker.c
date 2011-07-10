
#include <sys/mman.h>
#include <stdio.h>

#include "mmap_tracker.h"

mmap_tracker_t*
make_tracked_mmap_existing(pTHX_ size_t length, void* mmap_address)
{
  mmap_tracker_t* tracker;
  Newx(tracker, 1, mmap_tracker_t);
  tracker->mmap_address = mmap_address;
  tracker->length = length;
  tracker->refcount = 0;
  return tracker;
}

mmap_tracker_t*
make_tracked_mmap_fd(pTHX_ size_t length, int prot, int flags, int fd, int offset)
{
  void* addr = (void*)mmap(0, (size_t)length, prot, flags, fd, offset);
  return make_tracked_mmap_existing(aTHX_ length, addr);
}

mmap_tracker_t*
make_tracked_mmap_file(pTHX_ size_t length, int prot, int flags, const char* filename, int offset)
{
  int fd;
  FILE* mapfile;
  mapfile = fopen(filename, "r");
  if (mapfile == 0)
    croak("Failed to open file '%s' for reading: %i", filename, errno);
  fd = fileno(mapfile);
  return make_tracked_mmap_fd(aTHX_ length, prot, flags, fd, offset);
}

