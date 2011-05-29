#ifndef xs_bucket_h_
#define xs_bucket_h_


typedef struct {
  IV id;
  ssize_t coords_offset; /* really a double*, but see
                          * ASI_GET_COORDS/ASI_SET_COORDS macros */
} xs_item_t;

typedef struct {
  UV node_id;
  UV ndims;
  UV nitems;
  ssize_t items_offset; /* really an xs_item_t*, but see
                         * ASI_GET_ITEMS/ASI_SET_ITEMS macros */
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


#endif
