#include <stdio.h>
#include <sys/mman.h>

#define PERL_NO_GET_CONTEXT
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"


#include "xs_bucket.h"


MODULE = Algorithm::SpatialIndex::Bucket::XS PACKAGE = Algorithm::SpatialIndex::Bucket::XS

void
debug_dump(self)
    xs_bucket_t* self
  PPCODE:
    dump_bucket(self);

xs_bucket_t*
invariant_clone(self)
    xs_bucket_t* self
  PREINIT:
    /* FIXME hack breaking inheritance */
    const char* CLASS = "Algorithm::SpatialIndex::Bucket::XS";
  CODE:
    /* this is all for testing only */
    RETVAL = (xs_bucket_t*)invariant_bucket_clone(aTHX_ self, 0, 0); /* bucket, target_addr, is_mmap */
  OUTPUT: RETVAL

void
dump_as_string(self)
    xs_bucket_t* self
  PREINIT:
    xs_bucket_t* buckclone;
    STRLEN len;
    SV* retval;
    char* content;
  PPCODE:
    /* FIXME this is really inefficient... copying memory all over the place.
     * The commented out version below doesn't seem to work. No idea why. */
    len = bucket_mem_size(aTHX_ self);
    Newx(content, len+1, char);
    buckclone = invariant_bucket_clone(aTHX_ self, content, 0); /* no need for the bucket to free anything */
    printf("ASIf_ free mode DUMP: %i\n", (int)(buckclone->free_mode));
    retval = newSVpv(content, len+1);
    Safefree(content);
    XPUSHs(sv_2mortal(retval));
    /*
    retval = newSV(len);
    SvPOK_on(retval);
    content = SvPVX(retval);
    buckclone = invariant_bucket_clone(aTHX_ self, content, 0);
    content[len] = '\0';
    XPUSHs(sv_2mortal(retval));
    */

AV*
_new_buckets_from_mmap_file(CLASS, file, filelen, buckets_pos)
    char* CLASS;
    char* file;
    UV filelen;
    AV* buckets_pos;
  PREINIT:
    FILE* mapfile;
    int fd;
    size_t buck_pos;
    char* bucks_str;
    UV i, nbuckets;
    xs_bucket_t* curbuck;
    SV** elem;
    AV* inner_av;
    SV *thesv, *thesv2;
  CODE:
    /* The problem here is that the code assumes that a bucket
     * (with all of its contents!) has constant size and simply
     * casting the mmapped data to the proper type is going to
     * work. It doesn't. It needs some form of index to figure out
     * where each bucket starts.
     *
     * Not only that. While the buckets will be marked "no free"
     * for the destructor, the mmapped memory will never be released.
     * The proper solution is still unclear. Possibly this needs
     * refcounting from each bucket to its underlying mmap.
     *
     * Update: The refcounting facilities are now implemented and await
     * exploitation!
     */
    nbuckets = av_len(buckets_pos)+1;

    mapfile = fopen(file, "r");
    if (mapfile == 0) {
      croak("Failed to open file '%s' for reading: %i", file, errno);
    }
    fd = fileno(mapfile);
    RETVAL = newAV();
    sv_2mortal((SV*)RETVAL);
    av_fill(RETVAL, nbuckets-1);
    bucks_str = (char*) mmap(0, (size_t)filelen, PROT_READ, MAP_SHARED, fd, 0);
    for (i = 0; i < nbuckets; ++i) {
      elem = av_fetch(buckets_pos, i, 0);
      if (elem == 0 || !SvROK(*elem) || (SvTYPE(SvRV(*elem)) != SVt_PVAV))
      {
        croak("Error reading buckets from mmap file: Bucket position index array elem %u is not an array reference", i);
      }

      inner_av = (AV*)SvRV(*elem);
      if (av_len(inner_av) < 1)
      {
        croak("Error reading buckets from mmap file: Need at least two elements sub-array of bucket position index (bucket %u)", i);
      }
      /*node_id = SvIV(*av_fetch(inner_av, 0, 0));*/
      buck_pos = SvUV(*av_fetch(inner_av, 1, 0));
      curbuck = (xs_bucket_t*) (bucks_str + buck_pos);
      dump_bucket(curbuck);
      thesv = newSV(0);
      thesv2 = sv_setref_pv(thesv, CLASS, (void*)(curbuck));
      av_store(RETVAL, i, thesv2);
    }
  OUTPUT: RETVAL


xs_bucket_t*
_new_bucket(CLASS, node_id, items_av)
    char *CLASS
    UV node_id;
    AV* items_av;
  PREINIT:
    UV nitems;
    xs_item_t* items_ary;
    UV i, ndim;
    AV* item_av;
    xs_item_t* item;
  CODE:
    Newx(RETVAL, 1, xs_bucket_t);
    RETVAL->mmap_ref = 0; /* Not in an mmap */
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
    UV i, n, ndim;
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
  PPCODE:
    destroy_bucket(aTHX_ self);
    XSRETURN_EMPTY;

void
add_items(self, ...)
    xs_bucket_t* self
  PREINIT:
    AV *item_av;
    UV i, nitems, nitems_new, ndim;
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

