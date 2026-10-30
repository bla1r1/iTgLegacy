//
// TGLocklessRingBuffer.hpp - Single-Producer Single-Consumer (SPSC) lockless ring buffer.
//
#ifndef TGLOCKLESSRINGBUFFER_HPP
#define TGLOCKLESSRINGBUFFER_HPP

#include <atomic>
#include <cstddef>
#include <algorithm>
#include <cstring>

template <typename T, size_t Capacity = 8192>
class TGLocklessRingBuffer {
	static_assert((Capacity & (Capacity - 1)) == 0, "Capacity must be a power of 2");

private:
	T _buffer[Capacity];
	alignas(64) std::atomic<size_t> _writeIndex{0};
	alignas(64) std::atomic<size_t> _readIndex{0};

public:
	TGLocklessRingBuffer() {
		_writeIndex.store(0, std::memory_order_relaxed);
		_readIndex.store(0, std::memory_order_relaxed);
	}

	void clear() {
		_writeIndex.store(0, std::memory_order_relaxed);
		_readIndex.store(0, std::memory_order_relaxed);
	}

	size_t available_read() const {
		size_t w = _writeIndex.load(std::memory_order_acquire);
		size_t r = _readIndex.load(std::memory_order_relaxed);
		return w - r;
	}

	size_t available_write() const {
		size_t r = _readIndex.load(std::memory_order_acquire);
		size_t w = _writeIndex.load(std::memory_order_relaxed);
		return Capacity - (w - r);
	}

	size_t capacity() const {
		return Capacity;
	}

	size_t write(const T *data, size_t count) {
		if (!data || count == 0) return 0;
		size_t r = _readIndex.load(std::memory_order_acquire);
		size_t w = _writeIndex.load(std::memory_order_relaxed);
		size_t available = Capacity - (w - r);
		size_t toWrite = std::min(count, available);
		if (toWrite == 0) return 0;

		size_t mask = Capacity - 1;
		size_t part1 = std::min(toWrite, Capacity - (w & mask));
		std::memcpy(&_buffer[w & mask], data, part1 * sizeof(T));
		if (toWrite > part1) {
			std::memcpy(&_buffer[0], data + part1, (toWrite - part1) * sizeof(T));
		}

		_writeIndex.store(w + toWrite, std::memory_order_release);
		return toWrite;
	}

	size_t read(T *dest, size_t count) {
		if (!dest || count == 0) return 0;
		size_t w = _writeIndex.load(std::memory_order_acquire);
		size_t r = _readIndex.load(std::memory_order_relaxed);
		size_t available = w - r;
		size_t toRead = std::min(count, available);
		if (toRead == 0) return 0;

		size_t mask = Capacity - 1;
		size_t part1 = std::min(toRead, Capacity - (r & mask));
		std::memcpy(dest, &_buffer[r & mask], part1 * sizeof(T));
		if (toRead > part1) {
			std::memcpy(dest + part1, &_buffer[0], (toRead - part1) * sizeof(T));
		}

		_readIndex.store(r + toRead, std::memory_order_release);
		return toRead;
	}
};

#endif // TGLOCKLESSRINGBUFFER_HPP
