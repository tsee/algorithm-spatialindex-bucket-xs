#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

typedef struct {
  IV id;
  ssize_t coords_offset;
} xs_item_t;

typedef struct {
  UV node_id;
  UV ndims;
  UV nitems;
  ssize_t items_offset;
  char free_mode;
} xs_bucket_t;


/* settings in free_mode */
#define ASIf_NORMAL_FREE 0
#define ASIf_BLOCK_FREE 1
#define ASIf_NO_FREE 2


#define ASI_GET_OFFSET_MEMBER(pptr, membername, type) ( (type*)( (ssize_t)(pptr) + (pptr)->membername) )
#define ASI_SET_OFFSET_MEMBER(pptr, membername, dataptr) \
        STMT_START { \
          ( (pptr)->membername = (ssize_t) ((ssize_t)(dataptr) - (ssize_t)(pptr)) ); \
        } STMT_END


#define ASI_GET_ITEMS(pptr) ASI_GET_OFFSET_MEMBER(pptr, items_offset, xs_item_t)
#define ASI_SET_ITEMS(pptr, itemsptr) ASI_SET_OFFSET_MEMBER(pptr, items_offset, itemsptr)

#define ASI_GET_COORDS(itemptr) ASI_GET_OFFSET_MEMBER(itemptr, coords_offset, double)
#define ASI_SET_COORDS(itemptr, coordsptr) ASI_SET_OFFSET_MEMBER(itemptr, coords_offset, coordsptr)

#define ASI_RENEW_ITEMS(items_ary, nitems_old, nitems_new) \
        STMT_START { \
          UV i; \
          ssize_t move_offset; \
          xs_item_t* oldpos = items_ary; \
          Renew(items_ary, nitems_new, xs_item_t); \
          move_offset = (ssize_t) ((ssize_t)items_ary - (ssize_t)oldpos); \
          for (i = 0; i < nitems_old; ++i) { \
            /* FIXME breaks ASI_GET_OFFSET_MEMBER/etc encapsulation */ \
            items_ary[i].coords_offset -= move_offset; \
          } \
        } STMT_END

#define ASI_MAKE_ITEM_AV(item_av, itemptr, ndims) \
        STMT_START { \
          double* coords; \
          item_av = newAV(); \
          av_fill(item_av, ndims); /* 1 (for payload) + ndims-1*/ \
          av_store(item_av, 0, newSViv(itemptr->id)); \
          coords = ASI_GET_COORDS(itemptr); \
          for (j = 0; j < ndims; ++j) { \
            av_store(item_av, j+1, newSVnv(coords[j])); \
          } \
        } STMT_END


#define ASI_MAKE_ITEM(itemptr, item_av, ndim) \
        STMT_START { \
          double* tmp; \
          itemptr->id = SvIV(*av_fetch(item_av, 0, 0)); \
          Newx(tmp, ndim, double); \
          ASI_SET_COORDS(itemptr, tmp); \
          /* itemptr->coords = (double*)((char*)tmp-(char*)itemptr); */ \
          for (j = 0; j < ndim; ++j) \
            tmp[j] = SvNV(*av_fetch(item_av, j+1, 0)); \
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
  printf("- ndims: %u\n  nitems: %u  node_id: %u\n", (unsigned int)self->ndims, (unsigned int)n, (unsigned int)self->node_id);
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
char*
invariant_bucket_clone(pTHX_ xs_bucket_t* self, char* target)
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
  if (target == 0)
    ((xs_bucket_t*)str)->free_mode = ASIf_BLOCK_FREE;
  else
    ((xs_bucket_t*)str)->free_mode = ASIf_NO_FREE;

  if (nitems == 0) {
    return str;
  }

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

  return str;
}

MODULE = Algorithm::SpatialIndex::Bucket::XS PACKAGE = Algorithm::SpatialIndex::Bucket::XS

void
dump(self)
    xs_bucket_t* self
  PPCODE:
    dump_bucket(self);

xs_bucket_t*
invariant_clone(self)
    xs_bucket_t* self
  PREINIT:
    const char* CLASS = "Algorithm::SpatialIndex::Bucket::XS";
  CODE:
    /* this is all for testing only */
    RETVAL = (xs_bucket_t*)invariant_bucket_clone(aTHX_ self, 0);
  OUTPUT: RETVAL

xs_bucket_t*
_new_bucket(CLASS, node_id, items_av)
    char *CLASS
    UV node_id;
    AV* items_av;
  PREINIT:
    UV nitems;
    xs_item_t* items_ary;
    UV i, j, ndim;
    AV* item_av;
    xs_item_t* item;
  CODE:
    Newx(RETVAL, 1, xs_bucket_t);
    RETVAL->node_id = node_id;
    RETVAL->free_mode = ASIf_NORMAL_FREE;

    nitems = av_len(items_av)+1;
    RETVAL->nitems = nitems;

    if (nitems != 0) {
      Newx(items_ary, nitems, xs_item_t);
      ASI_SET_ITEMS(RETVAL, items_ary);
      /* RETVAL->items = (xs_item_t*)((char*)RETVAL-(char*)items_ary); */

      ndim = av_len((AV*)SvRV(*av_fetch(items_av, 0, 0)));
      RETVAL->ndims = ndim;
      for (i = 0; i < nitems; ++i) {
        item_av = (AV*)SvRV(*av_fetch(items_av, i, 0));
        item = &items_ary[i];
        ASI_MAKE_ITEM(item, item_av, ndim);
      }
    }
    else {
      RETVAL->ndims = 0;
      ASI_SET_ITEMS(RETVAL, 0);
    }
  OUTPUT:
    RETVAL

UV
node_id(self)
    xs_bucket_t* self
  CODE:
    RETVAL = self->node_id;
  OUTPUT: RETVAL


AV*
items(self)
    xs_bucket_t* self
  PREINIT:
    UV i, j, n, ndim;
    xs_item_t *items_ary, *itemptr;
    AV* item_av;
  CODE:
    RETVAL = newAV();
    sv_2mortal((SV*)RETVAL);
    n = self->nitems;
    if (n != 0) {
      av_fill(RETVAL, n-1);
      items_ary = ASI_GET_ITEMS(self);
      ndim = self->ndims;
      for (i = 0; i < n; ++i) {
        itemptr = &items_ary[i];
        ASI_MAKE_ITEM_AV(item_av, itemptr, ndim);
        av_store(RETVAL, i, newRV_noinc((SV*)item_av));
      }
    }
  OUTPUT: RETVAL

AV*
items_in_rect(self, ...)
    xs_bucket_t* self
  PREINIT:
    IV i, j, n, ndim;
    double *cmp_coords;
    double *item_coords;
    double item_coord;
    bool skip;
    AV* item_av;
    xs_item_t* items_ary;
    xs_item_t* itemptr;
  CODE:
    if (items < 5)
      croak("What? No rect coordinates?");
    else if (!items % 2) {
      croak("What? No even number of coordinates?");
    }

    /* TODO experiment with optimistic preallocation, but perl already does that... */
    RETVAL = newAV();
    sv_2mortal((SV*)RETVAL);
    items_ary = ASI_GET_ITEMS(self);
    n = self->nitems;

    if (n > 0) {
      /* get coords from stack */
      ndim = (unsigned int)(0.5*(items-1));
      Newx(cmp_coords, items-1, double);
      /* Newx(item_coords, ndim, double); */

      /* xl yl zl xu yu zu => xl xu yl yu zl zu */ 
      for (i = 1; i <= ndim; ++i) {
        cmp_coords[i*2-2] = SvNV(ST(i));
        cmp_coords[i*2-1] = SvNV(ST(i+ndim));
      }

      for (i = 0; i < n; ++i) {
        itemptr = &items_ary[i];
        skip = 0;
        item_coords = ASI_GET_COORDS(itemptr);
        for (j = 0; j < ndim; ++j) {
          item_coord = item_coords[j];
          if (item_coord < cmp_coords[j*2] || item_coord > cmp_coords[j*2+1]) {
            skip = 1;
            break;
          }
        }
        if (!skip) {
          ASI_MAKE_ITEM_AV(item_av, itemptr, ndim);
          av_push(RETVAL, newRV_noinc((SV*)item_av));
        }
      }
      Safefree(cmp_coords);
    } /* end if n > 0 */
  OUTPUT: RETVAL

void
DESTROY(self)
    xs_bucket_t* self
  PREINIT:
    UV i, n, ndims;
    xs_item_t* item_ary;
    double *coords;
  PPCODE:
    if (self->free_mode == ASIf_NORMAL_FREE) {
      ndims = self->ndims;
      n = self->nitems;
      item_ary = ASI_GET_ITEMS(self);
      for (i = 0; i < n; ++i) {
        coords = ASI_GET_COORDS(&item_ary[i]);
        Safefree(coords);
      }
      Safefree(item_ary);
    }
    if (self->free_mode != ASIf_NO_FREE) {
      Safefree(self);
    }
    XSRETURN_EMPTY;

void
add_items(self, ...)
    xs_bucket_t* self
  PREINIT:
    AV *item_av;
    UV i, j, nitems, nitems_new, ndim;
    xs_item_t* items_ary;
    xs_item_t* item;
  PPCODE:
    if (self->free_mode != ASIf_NORMAL_FREE) {
      croak("Cannot add items to invariant bucket");
    }
    if (items > 1) {
      nitems = self->nitems;
      nitems_new = nitems + items-1;
      self->nitems = nitems_new;
      if (nitems != 0) {
        /* FIXME implement geometric growth */
        items_ary = ASI_GET_ITEMS(self);
        /* printf("items_ary=%p items=%p  items_offset=%i\n", (void*)items_ary, (void*)ASI_GET_ITEMS(self), (int)self->items_offset); */
        /* Renew(items_ary, nitems_new, xs_item_t); */
        ASI_RENEW_ITEMS(items_ary, nitems, nitems_new);
        /* printf("items_ary=%p items=%p  items_offset=%i\n", (void*)items_ary, (void*)ASI_GET_ITEMS(self), (int)self->items_offset); */
      }
      else {
        /* FIXME SEGV if not RVs to AVs passed in */
        Newx(items_ary, nitems_new, xs_item_t);
        self->ndims = av_len((AV*)SvRV(ST(1)));
      }
      ASI_SET_ITEMS(self, items_ary);
      /* printf("items_ary=%p items=%p  items_offset=%i\n", (void*)items_ary, (void*)ASI_GET_ITEMS(self), (int)self->items_offset); */
      items_ary = ASI_GET_ITEMS(self);
      /* printf("items_ary=%p items=%p  items_offset=%i\n", (void*)items_ary, (void*)ASI_GET_ITEMS(self), (int)self->items_offset); */

      ndim = self->ndims;
      for (i = 1; i < (UV)items; ++i) {
        item_av = (AV*)SvRV(ST(i));
        item = &items_ary[nitems+i-1];
        /* printf("item=%p\n", item); */
        ASI_MAKE_ITEM(item, item_av, ndim);
      }
    }
    XSRETURN_EMPTY;

UV
nitems(self)
    xs_bucket_t* self
  CODE:
    RETVAL = self->nitems;
  OUTPUT: RETVAL

