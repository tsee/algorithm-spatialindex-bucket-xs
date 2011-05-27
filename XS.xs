#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

typedef struct {
  IV id;
  double* coords;
} xs_item_t;

typedef struct {
  UV node_id;
  UV ndims;
  UV nitems;
  xs_item_t* items;
  char free_mode;
} xs_bucket_t;


/* settings in free_mode */
#define ASIf_NORMAL_FREE 0
#define ASIf_BLOCK_FREE 1
#define ASIf_NO_FREE 2

#define ASI_MAKE_ITEM_AV(item_av, itemptr, ndims) \
      item_av = newAV(); \
      av_fill(item_av, ndims); /* 1 (for payload) + ndims-1*/ \
      av_store(item_av, 0, newSViv(itemptr->id)); \
      for (j = 0; j < ndims; ++j) { \
        av_store(item_av, j+1, newSVnv(itemptr->coords[j])); \
      }


#define ASI_MAKE_ITEM(itemptr, item_av, ndim) \
        STMT_START { \
          itemptr->id = SvIV(*av_fetch(item_av, 0, 0)); \
          Newx(itemptr->coords, ndim, double); \
          for (j = 0; j < ndim; ++j) \
            itemptr->coords[j] = SvNV(*av_fetch(item_av, j+1, 0)); \
        } STMT_END

STATIC
unsigned int
ASI_bucket_mem_size(pTHX_ xs_bucket_t* self)
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
ASI_invariant_bucket_clone(pTHX_ xs_bucket_t* self, char* target)
{
  UV i, n, ndim, coordsize;
  char *str, *ptr;
  xs_item_t* items;
  UV mem = ASI_bucket_mem_size(aTHX_ self);
  n = self->nitems;
  if (target == 0) {
    Newx(str, mem, char);
  }
  else {
    str = target;
  }

  Copy(self, str, 1, xs_bucket_t);
  if (target == 0)
    ((xs_bucket_t*)str)->free_mode = ASIf_BLOCK_FREE;
  else
    ((xs_bucket_t*)str)->free_mode = ASIf_NO_FREE;

  if (n == 0) {
    return str;
  }

  items = self->items;
  ndim = self->ndims;

  ptr = str+sizeof(xs_bucket_t);
  ((xs_bucket_t*)ptr)->items = (xs_item_t*)ptr;
  coordsize = ndim*sizeof(double);
  for (i = 0; i < n; ++i) {
    Copy(&items[i], ptr, 1, xs_item_t);
    ((xs_item_t*)ptr)->coords = (double*)(ptr+sizeof(xs_item_t));
    ptr += sizeof(xs_item_t);
    Copy(items[i].coords, ptr, ndim, double);
    ptr += coordsize;
  }

  return str;
}

MODULE = Algorithm::SpatialIndex::Bucket::XS PACKAGE = Algorithm::SpatialIndex::Bucket::XS

xs_bucket_t*
invariant_clone(self)
    xs_bucket_t* self
  PREINIT:
    const char* CLASS = "Algorithm::SpatialIndex::Bucket::XS";
  CODE:
    /* this is all for testing only */
    RETVAL = (xs_bucket_t*)ASI_invariant_bucket_clone(aTHX_ self, 0);
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
      RETVAL->items = items_ary;

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
      RETVAL->items = NULL;
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
      items_ary = self->items;
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
    double *coords;
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
    items_ary = self->items;
    n = self->nitems;

    if (n > 0) {
      /* get coords from stack */
      ndim = (unsigned int)(0.5*(items-1));
      Newx(coords, items-1, double);
      /* Newx(item_coords, ndim, double); */

      /* xl yl zl xu yu zu => xl xu yl yu zl zu */ 
      for (i = 1; i <= ndim; ++i) {
        coords[i*2-2] = SvNV(ST(i));
        coords[i*2-1] = SvNV(ST(i+ndim));
      }

      for (i = 0; i < n; ++i) {
        itemptr = &items_ary[i];
        skip = 0;
        for (j = 0; j < ndim; ++j) {
          item_coord = itemptr->coords[j];
          if (item_coord < coords[j*2] || item_coord > coords[j*2+1]) {
            skip = 1;
            break;
          }
        }
        if (!skip) {
          ASI_MAKE_ITEM_AV(item_av, itemptr, ndim);
          av_push(RETVAL, newRV_noinc((SV*)item_av));
        }
      }
      /* Safefree(item_coords) */;
      Safefree(coords);
    } /* end if n > 0 */
  OUTPUT: RETVAL

void
DESTROY(self)
    xs_bucket_t* self
  PREINIT:
    UV i, n, ndims;
    xs_item_t* item_ary;
  PPCODE:
    if (self->free_mode == ASIf_NORMAL_FREE) {
      ndims = self->ndims;
      n = self->nitems;
      item_ary = self->items;
      for (i = 0; i < n; ++i) {
        Safefree(item_ary[i].coords);
      }
      Safefree(self->items);
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
        Renew(self->items, nitems_new, xs_item_t);
      }
      else {
        Newx(self->items, nitems_new, xs_item_t);
        /* FIXME SEGV if no RVs to AVs passed in */
        self->ndims = av_len((AV*)SvRV(ST(1)));
      }

      ndim = self->ndims;
      items_ary = self->items;
      for (i = 1; i < (UV)items; ++i) {
        item_av = (AV*)SvRV(ST(i));
        item = &items_ary[nitems+i-1];
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

