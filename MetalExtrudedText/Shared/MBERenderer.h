
#import <MetalKit/MetalKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MBERenderer : NSObject <MTKViewDelegate>

@property (nonatomic, readonly, strong) MDLVertexDescriptor *vertexDescriptor;
@property (nonatomic, strong) MTKMesh *mesh;

-(instancetype)initWithView:(MTKView *)view;

@end

NS_ASSUME_NONNULL_END
