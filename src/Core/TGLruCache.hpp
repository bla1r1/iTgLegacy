//
// TGLruCache.hpp - Generic, bounded C++ LRU cache with deterministic O(1) eviction.
//
#ifndef TGLRUCACHE_HPP
#define TGLRUCACHE_HPP

#include <unordered_map>
#include <list>
#include <utility>
#include <cstddef>

template <typename Key, typename Value, typename Hash = std::hash<Key>>
class TGLruCache {
public:
	typedef std::pair<Key, Value> ItemPair;
	typedef typename std::list<ItemPair>::iterator ListIterator;

private:
	size_t _capacity;
	std::list<ItemPair> _items;
	std::unordered_map<Key, ListIterator, Hash> _index;

public:
	explicit TGLruCache(size_t capacity = 500) : _capacity(capacity ? capacity : 1) {}

	bool get(const Key &key, Value &outValue) {
		auto it = _index.find(key);
		if (it == _index.end()) {
			return false;
		}
		_items.splice(_items.begin(), _items, it->second);
		outValue = it->second->second;
		return true;
	}

	Value *get_ptr(const Key &key) {
		auto it = _index.find(key);
		if (it == _index.end()) {
			return nullptr;
		}
		_items.splice(_items.begin(), _items, it->second);
		return &(it->second->second);
	}

	bool contains(const Key &key) const {
		return _index.find(key) != _index.end();
	}

	void put(const Key &key, const Value &value) {
		auto it = _index.find(key);
		if (it != _index.end()) {
			_items.splice(_items.begin(), _items, it->second);
			it->second->second = value;
			return;
		}

		if (_items.size() >= _capacity) {
			auto last = _items.end();
			--last;
			_index.erase(last->first);
			_items.pop_back();
		}

		_items.emplace_front(key, value);
		_index[key] = _items.begin();
	}

	bool remove(const Key &key) {
		auto it = _index.find(key);
		if (it == _index.end()) {
			return false;
		}
		_items.erase(it->second);
		_index.erase(it);
		return true;
	}

	void clear() {
		_items.clear();
		_index.clear();
	}

	size_t size() const {
		return _items.size();
	}

	size_t capacity() const {
		return _capacity;
	}

	bool empty() const {
		return _items.empty();
	}

	void set_capacity(size_t newCapacity) {
		_capacity = newCapacity ? newCapacity : 1;
		while (_items.size() > _capacity) {
			auto last = _items.end();
			--last;
			_index.erase(last->first);
			_items.pop_back();
		}
	}
};

#endif // TGLRUCACHE_HPP
