#ifndef offset_members_h_
#define offset_members_h_

/* Access a struct member that's implemented with offset logic.
 * This means storing the relative position of the (pointer) member
 * instead of the pointer itself. This macro does the simple arithmetic
 * to return the absolute pointer position and does the proper cast. */
#define GET_OFFSET_MEMBER(pptr, membername, type)          \
        ( (type*)( (ssize_t)(pptr) + (pptr)->membername) )

/* Set a struct member that's implemented with offset logic */
#define SET_OFFSET_MEMBER(pptr, membername, dataptr)                                 \
        STMT_START {                                                                 \
          ( (pptr)->membername = (ssize_t) ((ssize_t)(dataptr) - (ssize_t)(pptr)) ); \
        } STMT_END



#endif
