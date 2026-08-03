// RunCat Neo temperature-only sensor reader for Apple Silicon.
//
// This external Custom Metrics provider reads only temperature sensors. It uses
// AppleSMC temperature keys first, then falls back to Apple Silicon HID sensors.
// The SMC protocol portion is derived from mactop under the MIT License; see
// LICENSE-mactop.txt. The HID sensor matching is derived from MacMonitor under
// the MIT License; see LICENSE-MacMonitor.txt.

#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <mach/mach.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef matching);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef key);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int options, uint64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

enum {
    AppleVendorUsagePage = 0xff00,
    AppleVendorTemperatureSensorUsage = 0x0005,
    TemperatureEventType = 15,
    SMCUserClientMethod = 2,
    SMCReadBytesCommand = 5,
    SMCReadIndexCommand = 8,
    SMCReadKeyInfoCommand = 9,
    SMCTemperatureKeyLimit = 32,
};

typedef struct {
    char major;
    char minor;
    char build;
    char reserved;
    unsigned short release;
} SMCVersion;

typedef struct {
    unsigned short version;
    unsigned short length;
    unsigned int cpuPLimit;
    unsigned int gpuPLimit;
    unsigned int memPLimit;
} SMCPLimitData;

typedef struct {
    unsigned int dataSize;
    unsigned int dataType;
    char dataAttributes;
} SMCKeyInfo;

typedef struct {
    unsigned int key;
    SMCVersion version;
    SMCPLimitData pLimitData;
    SMCKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    unsigned int data32;
    char bytes[32];
} SMCKeyData;

typedef struct {
    char key[5];
    unsigned int dataSize;
    unsigned int dataType;
} SMCTemperatureKey;

static volatile sig_atomic_t keepRunning = 1;
static BOOL loadedSMCKeys = NO;
static SMCTemperatureKey cpuSMCKeys[SMCTemperatureKeyLimit];
static int cpuSMCKeyCount = 0;
static SMCTemperatureKey gpuSMCKeys[SMCTemperatureKeyLimit];
static int gpuSMCKeyCount = 0;

static void stopReading(int signalNumber) {
    (void)signalNumber;
    keepRunning = 0;
}

static BOOL isValidTemperature(double value) {
    return value > 10.0 && value < 150.0;
}

static unsigned int fourCC(const char *value) {
    return ((unsigned int)(unsigned char)value[0] << 24) |
        ((unsigned int)(unsigned char)value[1] << 16) |
        ((unsigned int)(unsigned char)value[2] << 8) |
        (unsigned int)(unsigned char)value[3];
}

static kern_return_t smcCall(io_connect_t connection, SMCKeyData *input, SMCKeyData *output) {
    size_t inputSize = sizeof(*input);
    size_t outputSize = sizeof(*output);
    kern_return_t result = IOConnectCallStructMethod(connection, SMCUserClientMethod,
        input, inputSize, output, &outputSize);
    if (result != kIOReturnSuccess) {
        return result;
    }
    return output->result == 0 ? kIOReturnSuccess : kIOReturnError;
}

static io_connect_t openSMC(void) {
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"),
            &iterator) != kIOReturnSuccess) {
        return 0;
    }

    io_object_t service = IOIteratorNext(iterator);
    IOObjectRelease(iterator);
    if (service == 0) {
        return 0;
    }

    io_connect_t connection = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return result == kIOReturnSuccess ? connection : 0;
}

static kern_return_t getSMCKeyAtIndex(io_connect_t connection, int index, char key[5]) {
    SMCKeyData input = {0};
    SMCKeyData output = {0};
    input.data8 = SMCReadIndexCommand;
    input.data32 = (unsigned int)index;
    kern_return_t result = smcCall(connection, &input, &output);
    if (result != kIOReturnSuccess) {
        return result;
    }

    key[0] = (char)(output.key >> 24);
    key[1] = (char)(output.key >> 16);
    key[2] = (char)(output.key >> 8);
    key[3] = (char)output.key;
    key[4] = '\0';
    return kIOReturnSuccess;
}

static kern_return_t getSMCKeyInfo(io_connect_t connection, const char key[5], SMCKeyInfo *info) {
    SMCKeyData input = {0};
    SMCKeyData output = {0};
    input.key = fourCC(key);
    input.data8 = SMCReadKeyInfoCommand;
    kern_return_t result = smcCall(connection, &input, &output);
    if (result == kIOReturnSuccess) {
        *info = output.keyInfo;
    }
    return result;
}

static kern_return_t readSMCKey(io_connect_t connection, const SMCTemperatureKey *key, char bytes[32]) {
    SMCKeyData input = {0};
    SMCKeyData output = {0};
    input.key = fourCC(key->key);
    input.keyInfo.dataSize = key->dataSize;
    input.data8 = SMCReadBytesCommand;
    kern_return_t result = smcCall(connection, &input, &output);
    if (result == kIOReturnSuccess) {
        memcpy(bytes, output.bytes, sizeof(output.bytes));
    }
    return result;
}

static BOOL isTemperatureDataType(unsigned int type) {
    return type == fourCC("flt ") || type == fourCC("sp78");
}

static void loadSMCTemperatureKeys(io_connect_t connection) {
    if (loadedSMCKeys || connection == 0) {
        return;
    }
    loadedSMCKeys = YES;

    SMCTemperatureKey keyCountDescriptor = {"#KEY", 4, fourCC("ui32")};
    char bytes[32] = {0};
    if (readSMCKey(connection, &keyCountDescriptor, bytes) != kIOReturnSuccess) {
        return;
    }
    unsigned int keyCount = ((unsigned int)(unsigned char)bytes[0] << 24) |
        ((unsigned int)(unsigned char)bytes[1] << 16) |
        ((unsigned int)(unsigned char)bytes[2] << 8) |
        (unsigned int)(unsigned char)bytes[3];

    for (unsigned int index = 0; index < keyCount; index++) {
        char key[5] = {0};
        SMCKeyInfo info = {0};
        if (getSMCKeyAtIndex(connection, (int)index, key) != kIOReturnSuccess ||
            key[0] != 'T' || getSMCKeyInfo(connection, key, &info) != kIOReturnSuccess ||
            !isTemperatureDataType(info.dataType)) {
            continue;
        }

        SMCTemperatureKey *destination = NULL;
        int *destinationCount = NULL;
        if (key[1] == 'p' || key[1] == 'e' || key[1] == 's') {
            destination = cpuSMCKeys;
            destinationCount = &cpuSMCKeyCount;
        } else if (key[1] == 'g') {
            destination = gpuSMCKeys;
            destinationCount = &gpuSMCKeyCount;
        }
        if (destination == NULL || *destinationCount >= SMCTemperatureKeyLimit) {
            continue;
        }

        SMCTemperatureKey *sensor = &destination[*destinationCount];
        memcpy(sensor->key, key, sizeof(sensor->key));
        sensor->dataSize = info.dataSize;
        sensor->dataType = info.dataType;
        (*destinationCount)++;
    }
}

static double decodeSMCTemperature(const SMCTemperatureKey *key, const char bytes[32]) {
    if (key->dataType == fourCC("flt ") && key->dataSize >= sizeof(float)) {
        float value = 0;
        memcpy(&value, bytes, sizeof(value));
        return value;
    }
    if (key->dataType == fourCC("sp78") && key->dataSize >= 2) {
        int16_t fixedPoint = (int16_t)(((unsigned char)bytes[0] << 8) | (unsigned char)bytes[1]);
        return fixedPoint / 256.0;
    }
    return 0;
}

static double averageSMCTemperature(io_connect_t connection, SMCTemperatureKey *keys, int keyCount) {
    double total = 0;
    int count = 0;
    for (int index = 0; index < keyCount; index++) {
        char bytes[32] = {0};
        if (readSMCKey(connection, &keys[index], bytes) != kIOReturnSuccess) {
            continue;
        }
        double value = decodeSMCTemperature(&keys[index], bytes);
        if (isValidTemperature(value)) {
            total += value;
            count++;
        }
    }
    return count == 0 ? 0 : total / count;
}

static BOOL isCPUSensor(const char *product) {
    return strstr(product, "PMU tdie") != NULL ||
        strstr(product, "eACC") != NULL ||
        strstr(product, "pACC") != NULL ||
        strstr(product, "sACC") != NULL ||
        strstr(product, "mACC") != NULL;
}

static BOOL isGPUSensor(const char *product) {
    return strstr(product, "GPU") != NULL;
}

static double averageHIDTemperature(IOHIDEventSystemClientRef client, BOOL gpu) {
    if (client == NULL) {
        return 0;
    }
    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (services == NULL) {
        return 0;
    }

    double total = 0;
    int count = 0;
    for (CFIndex index = 0; index < CFArrayGetCount(services); index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        CFStringRef productRef = (CFStringRef)IOHIDServiceClientCopyProperty(service, CFSTR("Product"));
        if (productRef == NULL) {
            continue;
        }
        char product[512] = {0};
        CFStringGetCString(productRef, product, sizeof(product), kCFStringEncodingUTF8);
        CFRelease(productRef);
        if (gpu ? !isGPUSensor(product) : !isCPUSensor(product)) {
            continue;
        }

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, TemperatureEventType, 0, 0);
        if (event == NULL) {
            continue;
        }
        double value = IOHIDEventGetFloatValue(event, TemperatureEventType << 16);
        CFRelease(event);
        if (isValidTemperature(value)) {
            total += value;
            count++;
        }
    }
    CFRelease(services);
    return count == 0 ? 0 : total / count;
}

static IOHIDEventSystemClientRef createTemperatureClient(void) {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (client == NULL) {
        return NULL;
    }

    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(AppleVendorUsagePage),
        @"PrimaryUsage": @(AppleVendorTemperatureSensorUsage),
    };
    // This private API's return value is not a reliable success indicator across
    // macOS releases. The service query below determines whether matching worked.
    IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)matching);
    return client;
}

static void printUsage(const char *program) {
    fprintf(stderr, "Usage: %s [--interval seconds]\n", program);
}

int main(int argc, const char *argv[]) {
    unsigned int interval = 0;
    if (argc == 3 && strcmp(argv[1], "--interval") == 0) {
        char *end = NULL;
        unsigned long value = strtoul(argv[2], &end, 10);
        if (*argv[2] == '\0' || *end != '\0' || value == 0 || value > 3600) {
            printUsage(argv[0]);
            return 2;
        }
        interval = (unsigned int)value;
    } else if (argc != 1) {
        printUsage(argv[0]);
        return 2;
    }

    io_connect_t smc = openSMC();
    loadSMCTemperatureKeys(smc);
    IOHIDEventSystemClientRef hid = createTemperatureClient();
    if (smc == 0 && hid == NULL) {
        fprintf(stderr, "Unable to open AppleSMC or Apple Silicon HID temperature sensors.\n");
        return 1;
    }

    signal(SIGINT, stopReading);
    signal(SIGTERM, stopReading);
    do {
        double cpu = averageSMCTemperature(smc, cpuSMCKeys, cpuSMCKeyCount);
        double gpu = averageSMCTemperature(smc, gpuSMCKeys, gpuSMCKeyCount);
        if (!isValidTemperature(cpu)) {
            cpu = averageHIDTemperature(hid, NO);
        }
        if (!isValidTemperature(gpu)) {
            gpu = averageHIDTemperature(hid, YES);
        }
        if (!isValidTemperature(cpu) || !isValidTemperature(gpu)) {
            fprintf(stderr, "Unable to find separate valid CPU and GPU temperature sensors.\n");
            if (hid != NULL) {
                CFRelease(hid);
            }
            if (smc != 0) {
                IOServiceClose(smc);
            }
            return 1;
        }
        printf("{\"cpu_temp\":%.1f,\"gpu_temp\":%.1f}\n", cpu, gpu);
        fflush(stdout);
        if (interval == 0) {
            break;
        }
        for (unsigned int elapsed = 0; elapsed < interval && keepRunning; elapsed++) {
            sleep(1);
        }
    } while (keepRunning);

    if (hid != NULL) {
        CFRelease(hid);
    }
    if (smc != 0) {
        IOServiceClose(smc);
    }
    return 0;
}
