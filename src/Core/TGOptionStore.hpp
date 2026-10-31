//
// TGOptionStore.hpp - td_api options, typed, with no Foundation in sight.
//
// updateOption is the only way the server corrects itself after sign-in: a
// limit changes, a flag is flipped for the account, the clock is named. The
// app used to read an option once with getOption and keep the answer
// forever, so every correction was lost.
//
// Values live here rather than in an NSDictionary because the clock offset is
// read per message date, on a 800 MHz in-order core, and because this is the
// store Phase 2 of docs/C_CPP_MIGRATION_PLAN.md says the chat state joins
// later - starting it in Objective-C would only mean writing it twice.
//
#pragma once
#include <cstdint>
#include <cstdlib>
#include <string>
#include <unordered_map>

class TGOptionStore {
public:
	enum Kind { KindNone = 0, KindBoolean, KindInteger, KindString };

	void setBoolean(const std::string &name, bool value) {
		Value &v = _values[name];
		v.kind = KindBoolean;
		v.number = value ? 1 : 0;
		v.text.clear();
	}

	void setInteger(const std::string &name, int64_t value) {
		Value &v = _values[name];
		v.kind = KindInteger;
		v.number = value;
		v.text.clear();
		// The server names the time it thinks it is in this one option. An
		// iPhone 4 with a dead battery boots in 1970 or in 2012, which grades
		// every message date wrong - "today" for a year-old message.
		if (name == "unix_time")
			noteServerTime(value, (int64_t)::time(nullptr));
	}

	void setString(const std::string &name, const std::string &value) {
		Value &v = _values[name];
		v.kind = KindString;
		v.number = 0;
		v.text = value;
	}

	/// optionValueEmpty: the option is gone, not false. A caller that passes a
	/// fallback gets its own, which is what "empty" means on this side.
	void clear(const std::string &name) { _values.erase(name); }

	Kind kindOf(const std::string &name) const {
		Values::const_iterator it = _values.find(name);
		return it == _values.end() ? KindNone : it->second.kind;
	}

	bool booleanFor(const std::string &name, bool fallback) const {
		Values::const_iterator it = _values.find(name);
		if (it == _values.end() || it->second.kind != KindBoolean)
			return fallback;
		return it->second.number != 0;
	}

	int64_t integerFor(const std::string &name, int64_t fallback) const {
		Values::const_iterator it = _values.find(name);
		if (it == _values.end() || it->second.kind != KindInteger)
			return fallback;
		return it->second.number;
	}

	std::string stringFor(const std::string &name, const char *fallback) const {
		Values::const_iterator it = _values.find(name);
		if (it == _values.end() || it->second.kind != KindString)
			return fallback ? std::string(fallback) : std::string();
		return it->second.text;
	}

	/// Seconds to add to this device's clock to get the server's.
	void noteServerTime(int64_t serverUnix, int64_t deviceUnix) {
		if (serverUnix <= 0 || deviceUnix <= 0)
			return;
		int64_t delta = serverUnix - deviceUnix;
		// Under a minute is the round trip and the device's own drift. Taking
		// it would make two consecutive dates disagree for no reason.
		_clockOffset = (delta > 60 || delta < -60) ? (int32_t)delta : 0;
	}

	int32_t clockOffset() const { return _clockOffset; }
	int64_t now(int64_t deviceUnix) const { return deviceUnix + _clockOffset; }

	size_t size() const { return _values.size(); }
	void reset() { _values.clear(); _clockOffset = 0; }

private:
	struct Value {
		Kind        kind;
		int64_t     number;
		std::string text;
		Value() : kind(KindNone), number(0) {}
	};
	typedef std::unordered_map<std::string, Value> Values;

	Values  _values;
	int32_t _clockOffset = 0;
};
