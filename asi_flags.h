#ifndef asi_flags_h_
#define asi_flags_h_

/* settings in free_mode: Determines how data structures are to be freed */

/* Normal free: Use the ordinary strategy of objects comprised of sub-objects:
 *              Destroy inner-most first and at the end, destroy the main object.
 *              Eg. for buckets: Free the coordinates in all items, then the
 *              array of items, then the bucket */
#define ASIf_NORMAL_FREE 0

/* Block free: All space for the whole object was allocated in one go.
 * It can be freed with one call to Safefree.
 * Eg. a bucket and its items can be released with one Safefree
 * call on the bucket address. This is set when an invariant clone
 * of an object is created for dumping/memory mapping. */
#define ASIf_BLOCK_FREE 1

/* The object's memory is handled by something else. DESTROY does
 * not free memory. */
#define ASIf_NO_FREE 2

/* The object's memory is handled by the mmap tracker.
 * DESTROY does not free memory but hands responsibility to
 * the refcounting mmap tracker that is pointed to by the object. */
#define ASIf_MMAP_FREE 3

#endif
