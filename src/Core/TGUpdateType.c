#include "TGUpdateType.h"
#include <string.h>

typedef struct {
	TGUpdateType type;
	const char  *name;
	size_t       len;
} TGUpdateEntry;

static const TGUpdateEntry kTGUpdateEntries[] = {
#define TG_UPDATE_TABLE_ROW(sym, name) { sym, name, sizeof(name) - 1 },
	TG_HANDLED_UPDATES(TG_UPDATE_TABLE_ROW)
#undef TG_UPDATE_TABLE_ROW
};

// ponytail: linear scan over 23 names, length compared first so almost every
// row costs one integer compare. A perfect hash earns its keep past a hundred.
TGUpdateType TGUpdateTypeFor(const char *name, size_t len) {
	if (!name || !len)
		return TGUpdateUnknown;

	const size_t count = sizeof(kTGUpdateEntries) / sizeof(kTGUpdateEntries[0]);
	for (size_t i = 0; i < count; i++){
		if (kTGUpdateEntries[i].len == len &&
			memcmp(kTGUpdateEntries[i].name, name, len) == 0)
			return kTGUpdateEntries[i].type;
	}
	return TGUpdateUnknown;
}

int TGUpdateTypeIsUpdateName(const char *name, size_t len) {
	return name && len > 6 && memcmp(name, "update", 6) == 0;
}
