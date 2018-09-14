
#import "MBEViewController.h"
#import "MBERenderer.h"
#import "MBETextMesh.h"

@implementation MBEViewController

- (MTKView *)mtkView {
    return (MTKView *)self.view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self.mtkView.device = device;
    self.mtkView.sampleCount = 4;
    self.mtkView.clearColor = MTLClearColorMake(0.85, 0.85, 0.85, 1.0);

    self.renderer = [[MBERenderer alloc] initWithView:self.mtkView];

    [self.renderer mtkView:self.mtkView drawableSizeWillChange:self.mtkView.bounds.size];

    self.mtkView.delegate = self.renderer;
    
    MTKMeshBufferAllocator *bufferAllocator = [[MTKMeshBufferAllocator alloc] initWithDevice:device];
    CTFontRef font = CTFontCreateWithName((__bridge CFStringRef)@"HoeflerText-Black", 72, NULL);
    MTKMesh *textMesh = [MBETextMesh meshWithString:@"Hello, world!"
                                            font:font
                                  extrusionDepth:16.0
                                vertexDescriptor:self.renderer.vertexDescriptor
                                 bufferAllocator:bufferAllocator];
    CFRelease(font);
    
    self.renderer.mesh = textMesh;
}

@end
