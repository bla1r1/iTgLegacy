//
// TGOptions.mm - one process-wide TGOptionStore behind the C API.
//
#import "TGOptions.h"
#import "TGOptionStore.hpp"
#include <cstring>
#include <ctime>

// ponytail: a plain function-local static. TDLib's updates arrive on one
// thread and the readers are on the main one; a mutex here would be the first
// thing to appear if that ever stops being true.
static TGOptionStore &store(void) {
	static TGOptionStore s;
	return s;
}

void TGOptionSetBoolean(const char *name, int value) {
	if (name) store().setBoolean(name, value != 0);
}

void TGOptionSetInteger(const char *name, long long value) {
	if (name) store().setInteger(name, (int64_t)value);
}

void TGOptionSetString(const char *name, const char *value) {
	if (name) store().setString(name, value ? value : "");
}

void TGOptionClear(const char *name) {
	if (name) store().clear(name);
}

int TGOptionBoolean(const char *name, int fallback) {
	if (!name) return fallback;
	return store().booleanFor(name, fallback != 0) ? 1 : 0;
}

long long TGOptionInteger(const char *name, long long fallback) {
	if (!name) return fallback;
	return (long long)store().integerFor(name, (int64_t)fallback);
}

size_t TGOptionString(const char *name, char *out, size_t size) {
	if (!name || !out || size == 0) return 0;
	std::string value = store().stringFor(name, NULL);
	if (value.empty()){
		out[0] = '\0';
		return 0;
	}
	size_t len = value.size() < size - 1 ? value.size() : size - 1;
	std::memcpy(out, value.data(), len);
	out[len] = '\0';
	return len;
}

int TGOptionClockOffset(void) {
	return (int)store().clockOffset();
}

long long TGOptionNow(void) {
	return (long long)store().now((int64_t)std::time(NULL));
}

size_t TGOptionCount(void) {
	return store().size();
}

void TGOptionReset(void) {
	store().reset();
}
