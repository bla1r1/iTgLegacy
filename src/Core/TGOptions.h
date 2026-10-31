//
// TGOptions.h - the C face of TGOptionStore, for the Objective-C side.
//
// handleUpdate is a .m file and stays one; it hands the three option shapes
// td_api has over as scalars and never sees the store.
//
#pragma once
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void TGOptionSetBoolean(const char *name, int value);
void TGOptionSetInteger(const char *name, long long value);
void TGOptionSetString(const char *name, const char *value);
void TGOptionClear(const char *name);

int       TGOptionBoolean(const char *name, int fallback);
long long TGOptionInteger(const char *name, long long fallback);
/// Writes at most `size` bytes including the terminator. Returns the length
/// written, or 0 when the option is unset or is not a string.
size_t    TGOptionString(const char *name, char *out, size_t size);

/// Seconds between this device's clock and the server's, 0 until the server
/// has said. `TGOptionNow` is the one to format a date against.
int       TGOptionClockOffset(void);
long long TGOptionNow(void);

size_t TGOptionCount(void);
void   TGOptionReset(void);

#ifdef __cplusplus
}
#endif
