
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import "MBERenderer.h"

#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
typedef NSViewController NSUIViewController;
#else
#import <UIKit/UIKit.h>
typedef UIViewController NSUIViewController;
#endif

@interface MBEViewController : NSUIViewController

@property (nonatomic, strong, readonly) MTKView *mtkView;

@property (nonatomic, strong) MBERenderer *renderer;

@end
