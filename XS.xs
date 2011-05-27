#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

typedef struct {
  /*UV nitems;*/
  UV node_id;
  AV* items;
} xs_bucket_t;

MODULE = Algorithm::SpatialIndex::Bucket::XS PACKAGE = Algorithm::SpatialIndex::Bucket::XS

xs_bucket_t*
_new_bucket(CLASS, node_id, items)
    char *CLASS
    UV node_id;
    AV* items;
  CODE:
    Newx(RETVAL, 1, xs_bucket_t);
    /* RETVAL->nitems = 0; */
    RETVAL->node_id = node_id;
    RETVAL->items = items;
    SvREFCNT_inc((SV*)items); /* FIXME check this */
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
  CODE:
    RETVAL = self->items; /* FIXME check refcount */
  OUTPUT: RETVAL

AV*
items_in_rect(self, ...)
    xs_bucket_t* self
  PREINIT:
    IV i, j, n, ndim;
    AV* items_av;
    AV* item_av;
    double *coords;
    double item_coord;
    bool skip;
    SV* item_rv;
  CODE:
    if (items < 5)
      croak("What? No rect coordinates?");
    else if (!items % 2) {
      croak("What? No even number of coordinates?");
    }

    /* get coords from stack */
    ndim = (unsigned int)(0.5*(items-1));
    Newx(coords, items-1, double);
    /* Newx(item_coords, ndim, double); */

    /* xl yl zl xu yu zu => xl xu yl yu zl zu */ 
    for (i = 1; i <= ndim; ++i) {
      coords[i*2-2] = SvNV(ST(i));
      coords[i*2-1] = SvNV(ST(i+ndim));
    }

    items_av = self->items;
    n = av_len(items_av) + 1;
    /* TODO experiment with optimistic preallocation, but perl already does that... */
    RETVAL = newAV();
    sv_2mortal((SV*)RETVAL);

    /* FIXME can segfault if bad data in item_av */
    for (i = 0; i < n; ++i) {
      item_rv = *av_fetch(items_av, i, 0);
      item_av = (AV*)SvRV(item_rv);
      skip = 0;
      for (j = 0; j < ndim; ++j) {
        item_coord = SvNV(*av_fetch(item_av, j+1, 0));
        if (item_coord < coords[j*2] || item_coord > coords[j*2+1]) {
          skip = 1;
          break;
        }
      }
      if (!skip)
        av_push(RETVAL, newSVsv(item_rv));
    }
    /* Safefree(item_coords) */;
    Safefree(coords);
  OUTPUT: RETVAL

void
DESTROY(self)
    xs_bucket_t* self
  PREINIT:
  PPCODE:
    Safefree(self);
    XSRETURN_EMPTY;

void
add_items(self, ...)
    xs_bucket_t* self
  PREINIT:
    UV i;
    AV* items_av;
    SV* item;
  PPCODE:
    items_av = self->items;
    for (i = 1; i < items; ++i) {
      item = ST(i);
      SvREFCNT_inc(item);
      av_push(items_av, item); /* TODO no elements known, could preallocate */
    }
    XSRETURN_EMPTY;

unsigned int
nitems(self)
    xs_bucket_t* self
  CODE:
    RETVAL = av_len(self->items)+1;
  OUTPUT: RETVAL
