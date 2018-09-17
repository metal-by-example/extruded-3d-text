
#import <simd/simd.h>
#import <ModelIO/ModelIO.h>

#import "MBERenderer.h"

typedef struct {
    simd_float4x4 projectionMatrix;
    simd_float4x4 modelViewMatrix;
} Uniforms;

static const NSUInteger kMaxBuffersInFlight = 3;

static const size_t kUniformAlignment = 256;
static const size_t kAlignedUniformsSize = ((sizeof(Uniforms) + kUniformAlignment - 1) / kUniformAlignment) * kUniformAlignment;

@interface MBERenderer ()
@property (nonatomic, strong) id <MTLDevice> device;
@property (nonatomic, strong) id <MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id <MTLRenderPipelineState> renderPipelineState;
@property (nonatomic, strong) id <MTLDepthStencilState> depthStencilState;

@property (nonatomic, strong) dispatch_semaphore_t frameBoundarySemaphore;
@property (nonatomic, assign) uint32_t uniformBufferOffset;
@property (nonatomic, assign) uint8_t uniformBufferIndex;
@property (nonatomic, strong) id <MTLBuffer> dynamicUniformBuffer;

@property (nonatomic, strong) id <MTLTexture> baseColorTexture;

@property (nonatomic, assign) matrix_float4x4 projectionMatrix;
@property (nonatomic, assign) float rotation;
@end

@implementation MBERenderer

-(nonnull instancetype)initWithView:(nonnull MTKView *)view;
{
    self = [super init];
    if(self)
    {
        _device = view.device;
        _frameBoundarySemaphore = dispatch_semaphore_create(kMaxBuffersInFlight);
        [self loadMetalWithView:view];
        [self loadAssets];
    }

    return self;
}

- (void)loadMetalWithView:(nonnull MTKView *)view;
{
    view.depthStencilPixelFormat = MTLPixelFormatDepth32Float_Stencil8;
    view.colorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    
    _vertexDescriptor = [MDLVertexDescriptor new];
    _vertexDescriptor.attributes[0].format = MDLVertexFormatFloat3;
    _vertexDescriptor.attributes[0].offset = 0;
    _vertexDescriptor.attributes[0].bufferIndex = 0;
    _vertexDescriptor.attributes[0].name = MDLVertexAttributePosition;
    _vertexDescriptor.attributes[1].format = MDLVertexFormatFloat3;
    _vertexDescriptor.attributes[1].offset = sizeof(float) * 3;
    _vertexDescriptor.attributes[1].bufferIndex = 0;
    _vertexDescriptor.attributes[1].name = MDLVertexAttributeNormal;
    _vertexDescriptor.attributes[2].format = MDLVertexFormatFloat2;
    _vertexDescriptor.attributes[2].offset = sizeof(float) * 6;
    _vertexDescriptor.attributes[2].bufferIndex = 0;
    _vertexDescriptor.attributes[2].name = MDLVertexAttributeTextureCoordinate;
    _vertexDescriptor.layouts[0].stride = sizeof(float) * 8;

    id<MTLLibrary> defaultLibrary = [self.device newDefaultLibrary];
    id <MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertex_main"];
    id <MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragment_main"];

    MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineStateDescriptor.sampleCount = view.sampleCount;
    pipelineStateDescriptor.vertexFunction = vertexFunction;
    pipelineStateDescriptor.fragmentFunction = fragmentFunction;
    pipelineStateDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(self.vertexDescriptor);
    pipelineStateDescriptor.sampleCount = view.sampleCount;
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
    pipelineStateDescriptor.depthAttachmentPixelFormat = view.depthStencilPixelFormat;
    pipelineStateDescriptor.stencilAttachmentPixelFormat = view.depthStencilPixelFormat;

    NSError *error = NULL;
    _renderPipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor error:&error];
    if (!_renderPipelineState) {
        NSLog(@"Failed to created pipeline state, error %@", error);
    }

    MTLDepthStencilDescriptor *depthStateDesc = [[MTLDepthStencilDescriptor alloc] init];
    depthStateDesc.depthCompareFunction = MTLCompareFunctionLess;
    depthStateDesc.depthWriteEnabled = YES;
    _depthStencilState = [_device newDepthStencilStateWithDescriptor:depthStateDesc];

    NSUInteger uniformBufferSize = kAlignedUniformsSize * kMaxBuffersInFlight;

    _dynamicUniformBuffer = [_device newBufferWithLength:uniformBufferSize
                                                 options:MTLResourceStorageModeShared];

    _commandQueue = [_device newCommandQueue];
}

- (void)loadAssets
{
    NSError *error;

    MTKTextureLoader* textureLoader = [[MTKTextureLoader alloc] initWithDevice:_device];

    NSDictionary *textureLoaderOptions = @{
      MTKTextureLoaderOptionTextureUsage       : @(MTLTextureUsageShaderRead),
      MTKTextureLoaderOptionTextureStorageMode : @(MTLStorageModePrivate)
    };

    _baseColorTexture = [textureLoader newTextureWithName:@"wood"
                                      scaleFactor:1.0
                                           bundle:nil
                                          options:textureLoaderOptions
                                            error:&error];

    if(!_baseColorTexture)
    {
        NSLog(@"Error creating texture %@", error.localizedDescription);
    }
}

- (void)updateWithTimestep:(NSTimeInterval)timestep
{
    self.uniformBufferIndex = (self.uniformBufferIndex + 1) % kMaxBuffersInFlight;
    
    self.uniformBufferOffset = kAlignedUniformsSize * self.uniformBufferIndex;
    
    Uniforms *uniforms = (Uniforms *)(self.dynamicUniformBuffer.contents + self.uniformBufferOffset);

    uniforms->projectionMatrix = self.projectionMatrix;

    vector_float3 axis = { 1, 1, 0 };
    matrix_float4x4 modelMatrix = simd_mul(matrix4x4_rotation(self.rotation, axis), matrix4x4_scale(0.02));
    matrix_float4x4 viewMatrix = matrix4x4_translation(0.0, 0.0, -8.0);

    uniforms->modelViewMatrix = matrix_multiply(viewMatrix, modelMatrix);

    self.rotation += timestep;
}

- (void)drawInMTKView:(nonnull MTKView *)view
{
    dispatch_semaphore_wait(_frameBoundarySemaphore, DISPATCH_TIME_FOREVER);

    id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];

    __block dispatch_semaphore_t block_sema = _frameBoundarySemaphore;
    [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
         dispatch_semaphore_signal(block_sema);
     }];
    
    NSTimeInterval timestep = (view.preferredFramesPerSecond > 0) ? 1.0 / view.preferredFramesPerSecond : 1.0 / 60;

    [self updateWithTimestep:timestep];

    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;

    if(renderPassDescriptor != nil) {
        id <MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];

        [renderEncoder setFrontFacingWinding:MTLWindingCounterClockwise];
        [renderEncoder setCullMode:MTLCullModeBack];
        [renderEncoder setRenderPipelineState:self.renderPipelineState];
        [renderEncoder setDepthStencilState:self.depthStencilState];

        [renderEncoder setVertexBuffer:self.dynamicUniformBuffer offset:self.uniformBufferOffset atIndex:1];

        int i = 0;
        for (MTKMeshBuffer *vertexBuffer in self.mesh.vertexBuffers) {
            if ([vertexBuffer isKindOfClass:[MTKMeshBuffer class]]) {
                [renderEncoder setVertexBuffer:vertexBuffer.buffer offset:vertexBuffer.offset atIndex:i++];
            }
        }

        [renderEncoder setFragmentTexture:self.baseColorTexture atIndex:0];

        for(MTKSubmesh *submesh in self.mesh.submeshes) {
            [renderEncoder drawIndexedPrimitives:submesh.primitiveType
                                      indexCount:submesh.indexCount
                                       indexType:submesh.indexType
                                     indexBuffer:submesh.indexBuffer.buffer
                               indexBufferOffset:submesh.indexBuffer.offset];
        }

        [renderEncoder endEncoding];

        [commandBuffer presentDrawable:view.currentDrawable];
    }

    [commandBuffer commit];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    float aspect = size.width / (float)size.height;
    _projectionMatrix = matrix_perspective_right_hand(65.0f * (M_PI / 180.0f), aspect, 0.1f, 100.0f);
}

#pragma mark Matrix utilities

matrix_float4x4 matrix4x4_translation(float tx, float ty, float tz)
{
    return (matrix_float4x4) {{
        { 1,   0,  0,  0 },
        { 0,   1,  0,  0 },
        { 0,   0,  1,  0 },
        { tx, ty, tz,  1 }
    }};
}

static matrix_float4x4 matrix4x4_scale(float s) {
    return (matrix_float4x4) {{
        { s,   0,  0,  0 },
        { 0,   s,  0,  0 },
        { 0,   0,  s,  0 },
        { 0,   0,  0,  1 }
    }};
}

static matrix_float4x4 matrix4x4_rotation(float radians, vector_float3 axis)
{
    axis = vector_normalize(axis);
    float ct = cosf(radians);
    float st = sinf(radians);
    float ci = 1 - ct;
    float x = axis.x, y = axis.y, z = axis.z;

    return (matrix_float4x4) {{
        { ct + x * x * ci,     y * x * ci + z * st, z * x * ci - y * st, 0},
        { x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0},
        { x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0},
        {                   0,                   0,                   0, 1}
    }};
}

matrix_float4x4 matrix_perspective_right_hand(float fovyRadians, float aspect, float nearZ, float farZ)
{
    float ys = 1 / tanf(fovyRadians * 0.5);
    float xs = ys / aspect;
    float zs = farZ / (nearZ - farZ);

    return (matrix_float4x4) {{
        { xs,   0,          0,  0 },
        {  0,  ys,          0,  0 },
        {  0,   0,         zs, -1 },
        {  0,   0, nearZ * zs,  0 }
    }};
}

@end
