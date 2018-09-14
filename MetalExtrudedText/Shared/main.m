
#import "MBEAppDelegate.h"

#if TARGET_OS_OSX

int main(int argc, const char * argv[]) {
    return NSApplicationMain(argc, argv);
}

#else

int main(int argc, char * argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([MBEAppDelegate class]));
    }
}

#endif
