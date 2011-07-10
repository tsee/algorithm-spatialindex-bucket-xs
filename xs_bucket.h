#ifndef xs_bucket_h_
#define xs_bucket_h_

#include "offset_members.h"
#include "mmap_tracker.h"
#include "asi_flags.h"

/* struct representing a single item in a bucket */
typedef struct {
  IV id;
  ssize_t coords_offset; /* really a double*, but see
                          * ASI_GET_COORDS/ASI_SET_COORDS macros */
} xs_item_t;

/* struct representing a bucket holding nitems items */
typedef struct {
  UV node_id;
  UV ndims;
  UV nitems;
  ssize_t items_offset; /* really an xs_item_t*, but see
                         * ASI_GET_ITEMS/ASI_SET_ITEMS macros */
  char free_mode; /* holds a flag indicating how to handle
                   * the bucket during destruction.
                   * See the ASIf_* defines below */

  /* If not NULL, points to an mmap_tracker_t struct that
   * defines the mmap that this bucket is part of.
   * DESTROY as well as construction code needs to respect this
   * to pass on refcount changes.
   * This is (obviously?) never serialized/dumped/written to disk
   * and thus doesn't need to be an offset member.
   */
  mmap_tracker_t* mmap_ref;
} xs_bucket_t;


/* Access the items array in a bucket (passed as a xs_bucket_t*) */
#define ASI_GET_ITEMS(pptr) GET_OFFSET_MEMBER(pptr, items_offset, xs_item_t)
/* Set the items array (passed as a pointer) in a bucket (passed as a xs_bucket_t*) */
#define ASI_SET_ITEMS(pptr, itemsptr) SET_OFFSET_MEMBER(pptr, items_offset, itemsptr)

/* Access the coordinates array (double*) in a bucket item (passed as a xs_item_t*) */
#define ASI_GET_COORDS(itemptr) GET_OFFSET_MEMBER(itemptr, coords_offset, double)
/* Set the coordinates array (double*) in a bucket item (passed as a xs_item_t*) */
#define ASI_SET_COORDS(itemptr, coordsptr) SET_OFFSET_MEMBER(itemptr, coords_offset, coordsptr)

/* Reallocate the array of items in a bucket */
#define ASI_RENEW_ITEMS(items_ary, nitems_old, nitems_new)                \
        STMT_START {                                                      \
          UV i;                                                           \
          ssize_t move_offset;                                            \
          xs_item_t* oldpos = items_ary;                                  \
          Renew(items_ary, nitems_new, xs_item_t);                        \
          move_offset = (ssize_t) ((ssize_t)items_ary - (ssize_t)oldpos); \
          for (i = 0; i < nitems_old; ++i) {                              \
            /* FIXME breaks GET_OFFSET_MEMBER/etc encapsulation */        \
            items_ary[i].coords_offset -= move_offset;                    \
          }                                                               \
        } STMT_END

/* Convert the given item pointer (not struct member offset!)
 * to an AV* as [id, coords...] */
#define ASI_MAKE_ITEM_AV(item_av, itemptr, ndims)                         \
        STMT_START {                                                      \
          double* coords;                                                 \
          UV j;                                                           \
          (item_av) = newAV();                                            \
          av_fill((item_av), (ndims)); /* 1 (for payload) + ndims-1*/     \
          av_store((item_av), 0, newSViv(itemptr->id));                   \
          coords = ASI_GET_COORDS(itemptr);                               \
          for (j = 0; j < (UV)(ndims); ++j) {                             \
            av_store((item_av), j+1, newSVnv(coords[j]));                 \
          }                                                               \
        } STMT_END

/* Create a new item struct including allocation of ndim coordinate array */
#define ASI_MAKE_ITEM(itemptr, item_av, ndim)                             \
        STMT_START {                                                      \
          double* tmp;                                                    \
          UV j;                                                           \
          (itemptr)->id = SvIV(*av_fetch((item_av), 0, 0));               \
          Newx(tmp, (ndim), double);                                      \
          ASI_SET_COORDS((itemptr), tmp);                                 \
          /* itemptr->coords = (double*)((char*)tmp-(char*)itemptr); */   \
          for (j = 0; j < (UV)(ndim); ++j)                                \
            tmp[j] = SvNV(*av_fetch((item_av), j+1, 0));                  \
        } STMT_END

STATIC
void
dump_coords(UV n, double* coords)
{
  UV i;
  printf("    %u coords:", (unsigned int)n);
  for (i = 0; i < n; ++i) {
    printf(" %f", coords[i]);
  }
  printf("\n");
}

STATIC
void
dump_item(xs_bucket_t* self, xs_item_t* item)
{
  double* coords = ASI_GET_COORDS(item);
  printf("  - id: %i\n", (int)item->id);
  dump_coords(self->ndims, coords);
}

STATIC
void
dump_bucket(xs_bucket_t* self)
{
  UV i, n;
  xs_item_t* items_ptr;
  n = self->nitems;
  items_ptr = ASI_GET_ITEMS(self);
  printf("- ndims: %u\n  nitems: %u  node_id: %u free_mode: %i\n", (unsigned int)self->ndims, (unsigned int)n, (unsigned int)self->node_id, (int)self->free_mode);
  for (i = 0; i < n; ++i) {
    dump_item(self, &items_ptr[i]);
  }
}

STATIC
unsigned int
bucket_mem_size(pTHX_ xs_bucket_t* self)
{
  return sizeof(xs_bucket_t) + self->nitems * (sizeof(xs_item_t) + self->ndims * sizeof(double));
}

/*
 * Returns a copy of the object with all parts of the object allocated in
 * one block of memory. If not 0, the provided target pointer is assumed
 * to have the correct amount of pre-allocated memory.
 * Sets the 'free_mode' flag on the new object to ASI_BLOCK_FREE
 * if it had to allocate memory or to ASI_NO_FREE if the memory
 * was preallocated.
 */
STATIC
xs_bucket_t*
invariant_bucket_clone(pTHX_ xs_bucket_t* self, char* target, bool mmapped)
{
  UV i, nitems, ndim, total_items_size;
  char *str, *ptr, *tmp;
  xs_item_t* items_ary;
  double* coordsptr;

  UV mem = bucket_mem_size(aTHX_ self);
  nitems = self->nitems;
  if (target == 0)
    Newx(str, mem, char);
  else
    str = target;

  Copy(self, str, 1, xs_bucket_t);

  ((xs_bucket_t*)str)->mmap_ref = 0; /* We do not know of an mmap tracker,
                                      * so do not clone that of the original. */

  if (target == 0)
    ((xs_bucket_t*)str)->free_mode = ASIf_BLOCK_FREE;
  else if (mmapped)
    ((xs_bucket_t*)str)->free_mode = ASIf_MMAP_FREE;
  else
    ((xs_bucket_t*)str)->free_mode = ASIf_NO_FREE;

  if (nitems == 0)
    return (xs_bucket_t*)str;

  items_ary = ASI_GET_ITEMS(self);
  ndim = self->ndims;

  /* move the current position, "ptr" to the end of the main struct
   * where the items will be copied to */
  ptr = str+sizeof(xs_bucket_t);

  /* make the items_offset member point at the memory location right after
   * the main struct */
  ASI_SET_ITEMS((xs_bucket_t*)str, (xs_item_t*)ptr);
  /* printf("bucket_size=%i diff=%i\n", (int)sizeof(xs_bucket_t), (int)((long int)ptr-(long int)str)); */

  /* the amount of memory required for the coordinates of a single item */
  total_items_size = nitems*sizeof(xs_item_t);
  for (i = 0; i < nitems; ++i) {
    /* ptr is the new item's position in each loop iteration */

    /* copy the current item struct over */
    Copy(&items_ary[i], ptr, 1, xs_item_t);

    /* copy the item's coordinates */
    coordsptr = ASI_GET_COORDS(&items_ary[i]);
    tmp = ptr+total_items_size;
    Copy(coordsptr, tmp, ndim, double);

    /* update the coordinates offset in the previously copied item struct */
    /* printf("sizeof item=%i offset=%i\n", (int)sizeof(xs_item_t), (int)(((xs_item_t*)ptr)->coords_offset)); */
    ASI_SET_COORDS((xs_item_t*)ptr, tmp);
    /* printf("sizeof item=%i offset=%i\n", (int)sizeof(xs_item_t), (int)(((xs_item_t*)ptr)->coords_offset)); */

    ptr += sizeof(xs_item_t);
  }

  return (xs_bucket_t*)str;
}

STATIC
void
destroy_bucket(pTHX_ xs_bucket_t* self)
{
  UV i, n, ndims;
  xs_item_t* item_ary;
  double *coords;

  /* printf("ASIf_ free mode in DESTROY: %i\n", (int)(self->free_mode)); */

  switch (self->free_mode) {
  case ASIf_NORMAL_FREE:
    ndims = self->ndims;
    n = self->nitems;
    item_ary = ASI_GET_ITEMS(self);
    for (i = 0; i < n; ++i) {
      coords = ASI_GET_COORDS(&item_ary[i]);
      Safefree(coords);
    }
    Safefree(item_ary);
    Safefree(self);
    break;
  case ASIf_BLOCK_FREE:
    Safefree(self);
    break;
  case ASIf_MMAP_FREE:
    if (self->mmap_ref == 0)
      croak("Woah, shouldn't happen: bucket free mode is ASIf_MMAP_FREE, but there is no mmap_ref member pointer!");
    MMAP_DEC_REFCOUNT(self->mmap_ref);
    break;
  case ASIf_NO_FREE:
    /* printf("Not freeing bucket at all - it is in ASIf_NO_FREE mode\n"); */
    break;
  default:
    dump_bucket(self);
    croak("Woah, shouldn't happen: bucket free mode is '%i'", self->free_mode);
    break;
  };
}


#endif
