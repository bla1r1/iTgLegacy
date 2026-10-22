// ==============================================================================
// tlv_polyfill.c
// Polyfill for __tlv_bootstrap and __tlv_atexit for iOS < 9.0 dyld compatibility.
// ==============================================================================

#include <pthread.h>
#include <stdlib.h>
#include <stdint.h>

struct TLVDescriptor {
    void* (*thunk)(struct TLVDescriptor*);
    unsigned long key;
    unsigned long offset;
};

// 64KB static buffer for main thread thread-local variables during dyld startup
static char main_thread_tlv_storage[65536];

__attribute__((visibility("default")))
void* __tlv_bootstrap(struct TLVDescriptor* tlv) {
    if (!tlv) return NULL;
    
    // For main thread during startup and runtime fallback, return static storage + offset
    if (tlv->offset < sizeof(main_thread_tlv_storage)) {
        return &main_thread_tlv_storage[tlv->offset];
    }
    
    return NULL;
}

__attribute__((visibility("default")))
void __tlv_atexit(void (*dtor)(void*), void* obj) {
    (void)dtor;
    (void)obj;
}
