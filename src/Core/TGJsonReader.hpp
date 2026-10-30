//
// TGJsonReader.hpp - Zero-allocation C++ wrapper over yyjson for fast data extraction.
//
#ifndef TGJSONREADER_HPP
#define TGJSONREADER_HPP

#include "yyjson/yyjson.h"
#include <string>
#include <cstring>
#include <cstdlib>
#include <cstdint>

class TGJsonVal {
private:
	yyjson_val *_val;

public:
	TGJsonVal(yyjson_val *v = nullptr) : _val(v) {}

	bool is_valid() const { return _val != nullptr; }
	bool is_null() const { return !_val || yyjson_is_null(_val); }
	bool is_bool() const { return _val && yyjson_is_bool(_val); }
	bool is_int() const { return _val && yyjson_is_int(_val); }
	bool is_real() const { return _val && yyjson_is_real(_val); }
	bool is_str() const { return _val && yyjson_is_str(_val); }
	bool is_arr() const { return _val && yyjson_is_arr(_val); }
	bool is_obj() const { return _val && yyjson_is_obj(_val); }

	int64_t as_int64(int64_t def = 0) const {
		if (!_val) return def;
		if (yyjson_is_int(_val)) return yyjson_get_sint(_val);
		if (yyjson_is_uint(_val)) return (int64_t)yyjson_get_uint(_val);
		if (yyjson_is_str(_val)) {
			const char *s = yyjson_get_str(_val);
			return s ? std::strtoll(s, nullptr, 10) : def;
		}
		return def;
	}

	int32_t as_int32(int32_t def = 0) const {
		return (int32_t)as_int64(def);
	}

	bool as_bool(bool def = false) const {
		if (!_val) return def;
		if (yyjson_is_bool(_val)) return yyjson_get_bool(_val);
		if (yyjson_is_int(_val)) return yyjson_get_sint(_val) != 0;
		return def;
	}

	double as_double(double def = 0.0) const {
		if (!_val) return def;
		if (yyjson_is_real(_val)) return yyjson_get_real(_val);
		if (yyjson_is_int(_val)) return (double)yyjson_get_sint(_val);
		return def;
	}

	const char *as_str(const char *def = "") const {
		if (!_val || !yyjson_is_str(_val)) return def;
		const char *s = yyjson_get_str(_val);
		return s ? s : def;
	}

	size_t str_len() const {
		return (_val && yyjson_is_str(_val)) ? yyjson_get_len(_val) : 0;
	}

	TGJsonVal get(const char *key) const {
		if (!_val || !yyjson_is_obj(_val) || !key) return TGJsonVal(nullptr);
		return TGJsonVal(yyjson_obj_get(_val, key));
	}

	int64_t get_int64(const char *key, int64_t def = 0) const {
		return get(key).as_int64(def);
	}

	int32_t get_int32(const char *key, int32_t def = 0) const {
		return get(key).as_int32(def);
	}

	bool get_bool(const char *key, bool def = false) const {
		return get(key).as_bool(def);
	}

	const char *get_str(const char *key, const char *def = "") const {
		return get(key).as_str(def);
	}

	size_t arr_size() const {
		return (_val && yyjson_is_arr(_val)) ? yyjson_arr_size(_val) : 0;
	}

	TGJsonVal arr_at(size_t index) const {
		if (!_val || !yyjson_is_arr(_val)) return TGJsonVal(nullptr);
		return TGJsonVal(yyjson_arr_get(_val, index));
	}

	yyjson_val *raw() const { return _val; }
};

class TGJsonDoc {
private:
	yyjson_doc *_doc;

public:
	TGJsonDoc(const char *utf8, size_t len) {
		_doc = (utf8 && len > 0) ? yyjson_read(utf8, len, 0) : nullptr;
	}

	explicit TGJsonDoc(const char *utf8) {
		_doc = utf8 ? yyjson_read(utf8, std::strlen(utf8), 0) : nullptr;
	}

	~TGJsonDoc() {
		if (_doc) {
			yyjson_doc_free(_doc);
			_doc = nullptr;
		}
	}

	TGJsonDoc(const TGJsonDoc &) = delete;
	TGJsonDoc &operator=(const TGJsonDoc &) = delete;

	TGJsonDoc(TGJsonDoc &&other) noexcept : _doc(other._doc) {
		other._doc = nullptr;
	}

	TGJsonDoc &operator=(TGJsonDoc &&other) noexcept {
		if (this != &other) {
			if (_doc) yyjson_doc_free(_doc);
			_doc = other._doc;
			other._doc = nullptr;
		}
		return *this;
	}

	bool is_valid() const { return _doc != nullptr; }

	TGJsonVal root() const {
		return _doc ? TGJsonVal(yyjson_doc_get_root(_doc)) : TGJsonVal(nullptr);
	}
};

#endif // TGJSONREADER_HPP
