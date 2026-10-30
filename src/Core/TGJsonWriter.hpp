//
// TGJsonWriter.hpp - fluent JSON writer that formats straight into a buffer.
//
// Every outgoing TDLib request used to be built three times: the
// NSDictionary literal at the call site, a whole yyjson_mut_doc tree built
// from it node by node, and then the text. The middle one is pure overhead -
// a second tree of allocations, a boxed node per key and per value, thrown
// away a microsecond later - and on a 4S the app sends one of these for every
// avatar, thumbnail and read receipt.
//
// This writes the text directly. One growing std::string, no nodes, and the
// result is null-terminated so it can go to td_json_client_send as it stands.
//
//   TGJsonWriter w;
//   w.begin_object()
//     .field("@type", "downloadFile")
//     .field("file_id", (int64_t)fileId)
//     .field("synchronous", false)
//    .end_object();
//   td_send(client, w.c_str());
//
#ifndef TGJSONWRITER_HPP
#define TGJSONWRITER_HPP

#include <string>
#include <cstdio>
#include <cstring>
#include <cstdint>

class TGJsonWriter {
private:
	std::string _out;
	bool _needComma;

	void separate() {
		if (_needComma)
			_out.push_back(',');
		_needComma = true;
	}

	void append_escaped(const char *utf8, size_t len) {
		_out.push_back('"');
		for (size_t i = 0; i < len; i++) {
			unsigned char c = (unsigned char)utf8[i];
			switch (c) {
				case '"':  _out.append("\\\"", 2); break;
				case '\\': _out.append("\\\\", 2); break;
				case '\n': _out.append("\\n", 2);  break;
				case '\r': _out.append("\\r", 2);  break;
				case '\t': _out.append("\\t", 2);  break;
				case '\b': _out.append("\\b", 2);  break;
				case '\f': _out.append("\\f", 2);  break;
				default:
					if (c < 0x20) {
						// The only other thing JSON forbids raw. Everything
						// from 0x20 up, UTF-8 continuation bytes included,
						// goes through untouched.
						char esc[7];
						std::snprintf(esc, sizeof(esc), "\\u%04x", c);
						_out.append(esc);
					} else {
						_out.push_back((char)c);
					}
					break;
			}
		}
		_out.push_back('"');
	}

public:
	explicit TGJsonWriter(size_t reserve = 256) : _needComma(false) {
		_out.reserve(reserve);
	}

	void clear() {
		_out.clear();
		_needComma = false;
	}

	TGJsonWriter &begin_object() {
		separate();
		_out.push_back('{');
		_needComma = false;
		return *this;
	}

	TGJsonWriter &end_object() {
		_out.push_back('}');
		_needComma = true;
		return *this;
	}

	TGJsonWriter &begin_array() {
		separate();
		_out.push_back('[');
		_needComma = false;
		return *this;
	}

	TGJsonWriter &end_array() {
		_out.push_back(']');
		_needComma = true;
		return *this;
	}

	/// A key inside an object. The value that follows it writes no comma of
	/// its own, which is what keeps `key("a").str("b")` valid.
	TGJsonWriter &key(const char *k, size_t len = 0) {
		separate();
		append_escaped(k ? k : "", (k && !len) ? std::strlen(k) : len);
		_out.push_back(':');
		_needComma = false;
		return *this;
	}

	TGJsonWriter &str(const char *v, size_t len) {
		separate();
		append_escaped(v ? v : "", v ? len : 0);
		return *this;
	}

	TGJsonWriter &str(const char *v) {
		return str(v, v ? std::strlen(v) : 0);
	}

	TGJsonWriter &num(int64_t v) {
		separate();
		char buf[24];
		std::snprintf(buf, sizeof(buf), "%lld", (long long)v);
		_out.append(buf);
		return *this;
	}

	/// %.17g round-trips every double exactly, which an id arriving back as
	/// a real must do.
	TGJsonWriter &real(double v) {
		separate();
		char buf[40];
		std::snprintf(buf, sizeof(buf), "%.17g", v);
		_out.append(buf);
		return *this;
	}

	TGJsonWriter &boolean(bool v) {
		separate();
		_out.append(v ? "true" : "false");
		return *this;
	}

	TGJsonWriter &null_value() {
		separate();
		_out.append("null");
		return *this;
	}

	TGJsonWriter &field(const char *k, const char *v) { return key(k).str(v); }
	TGJsonWriter &field(const char *k, int64_t v)     { return key(k).num(v); }
	TGJsonWriter &field(const char *k, double v)      { return key(k).real(v); }
	TGJsonWriter &field(const char *k, bool v)        { return key(k).boolean(v); }

	/// Null-terminated, so it can be handed to td_json_client_send directly.
	const char *c_str() const { return _out.c_str(); }
	size_t size() const { return _out.size(); }
	const std::string &string() const { return _out; }
};

#endif // TGJSONWRITER_HPP
