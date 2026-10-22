#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <mach/mach_time.h>
#include <CoreFoundation/CoreFoundation.h>

typedef struct __IOHIDEvent * IOHIDEventRef;
typedef struct __IOHIDEventSystemClient * IOHIDEventSystemClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
extern IOHIDEventRef IOHIDEventCreateDigitizerFingerEvent(
    CFAllocatorRef allocator,
    uint64_t timeStamp,
    uint32_t index,
    uint32_t identity,
    uint32_t eventMask,
    float x,
    float y,
    float z,
    float tipPressure,
    float twist,
    bool range,
    bool touch,
    uint32_t options);

static void send_touch(IOHIDEventSystemClientRef client, float nx, float ny, bool down) {
    uint64_t now = mach_absolute_time();
    uint32_t mask = 0x3 | 0x4; // range (1) | touch (2) | position (4)
    IOHIDEventRef ev = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault,
        now,
        0, 0,
        mask,
        nx, ny, 0.0f,
        down ? 1.0f : 0.0f,
        0.0f,
        down ? true : false,
        down ? true : false,
        0
    );
    if (ev) {
        IOHIDEventSystemClientDispatchEvent(client, ev);
        CFRelease(ev);
    }
}

int main(int argc, char **argv) {
    float x = 0.5f;
    float y = 0.56f; // approximate center of OK button (537/960)
    if (argc >= 3) {
        x = atof(argv[1]);
        y = atof(argv[2]);
    }
    printf("Sending tap to (%.3f, %.3f)...\n", x, y);
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!client) {
        fprintf(stderr, "Failed to create IOHIDEventSystemClient\n");
        return 1;
    }

    send_touch(client, x, y, true);
    usleep(100000); // 100ms
    send_touch(client, x, y, false);
    CFRelease(client);
    printf("Tap dispatched successfully!\n");
    return 0;
}
