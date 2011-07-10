#ifndef mmap_tracker_h_
#define mmap_tracker_h_

#include <sys/types.h>
#include <EXTERN.h>
#include <perl.h>

/* struct representing an mmap'd region with a refcount*/
typedef struct {
  void* mmap_address;
  unsigned int refcount;
  size_t length;
} mmap_tracker_t;

/****************
 * Construction *
 ****************/

/* When creating a new mmap tracker, the refcount will be set to 0 */

/* Creates a new mmap tracker for an existing mmap using Perl's Newx malloc interface */
mmap_tracker_t* make_tracked_mmap_existing(pTHX_ size_t length, void* mmap_addr);

/* Creates a new mmap tracker for an open file via its fd using Perl's Newx malloc interface */
mmap_tracker_t* make_tracked_mmap_fd(pTHX_ size_t length, int prot, int flags, int fd, int offset);

/* Creates a new mmap tracker for a given file using Perl's Newx malloc interface */
mmap_tracker_t* make_tracked_mmap_file(pTHX_ size_t length, int prot, int flags, const char* filename, int offset);

/***********************
 * Access and refcount *
 ***********************/

/* Several of the macros in this section need access to a Perl context via pTHX or dTHX */

/* Fetch address of tracked mmap region */
#define MMAP_GET_ADDRESS(mmap_tracker) ((mmap_tracker)->mmap_address)

/* Fetch size of tracked mmap region */
#define MMAP_GET_LENGTH(mmap_tracker) ((mmap_tracker)->length)

/* Get/increment/decrement mmap refcounts */
#define MMAP_GET_REFCOUNT(mmap_tracker) ((mmap_tracker)->refcount)
#define MMAP_INC_REFCOUNT(mmap_tracker) (++((mmap_tracker)->refcount))

/* When decrementing the mmap refcount, the mmap may be automatically
 * mmunmapped and the tracker may be freed. */
#define MMAP_DEC_REFCOUNT(mmap_tracker)                                           \
    STMT_START {                                                                  \
      mmap_tracker_t* mm = (mmap_tracker);                                        \
      if (--(mm->refcount) == 0) {                                                \
        if (-1 == munmap(mm->mmap_address, mm->length)) {                         \
          croak("Failed to mmunmap address %p length %u",                         \
                (void*)mm->mmap_address,                                          \
                mm->length);                                                      \
        }                                                                         \
        Safefree(mm);                                                             \
      }                                                                           \
    } STMT_END

#endif /* mmap_tracker_h_ */

