
#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>
#import <CoreText/CoreText.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBETextMesh : NSObject

+ (MTKMesh *_Nullable)meshWithString:(NSString *)string
                                font:(CTFontRef)font
                      extrusionDepth:(CGFloat)depth
                    vertexDescriptor:(MDLVertexDescriptor *)vertexDescriptor
                     bufferAllocator:(MTKMeshBufferAllocator *)bufferAllocator;

@end

NS_ASSUME_NONNULL_END
