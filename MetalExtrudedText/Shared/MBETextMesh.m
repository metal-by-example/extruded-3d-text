
#import "MBETextMesh.h"
#import "MBETextTypes.h"
#import "tesselator.h"

#define USE_ADAPTIVE_SUBDIVISION 1
#define DEFAULT_QUAD_CURVE_SUBDIVISIONS 5

typedef UInt32 IndexType;

static inline float lerp(float a, float b, float t) {
    return a + t * (b - a);
}

static inline CGPoint lerpPoints(CGPoint a, CGPoint b, float t) {
    return CGPointMake(lerp(a.x, b.x, t), lerp(a.y, b.y, t));
}

// Maps a value t in a range [a, b] to the range [c, d]
static inline float remap(float a, float b, float c, float d, float t) {
    float p = (t - a) / (b - a);
    return c + p * (d - c);
}

static inline CGPoint evalQuadCurve(CGPoint a, CGPoint b, CGPoint c, CGFloat t) {
    CGPoint q0 = CGPointMake(lerp(a.x, c.x, t), lerp(a.y, c.y, t));
    CGPoint q1 = CGPointMake(lerp(c.x, b.x, t), lerp(c.y, b.y, t));
    CGPoint r = CGPointMake(lerp(q0.x, q1.x, t), lerp(q0.y, q1.y, t));
    return r;
}

@implementation MBETextMesh

+ (MTKMesh *_Nullable)meshWithString:(NSString *)string
                                font:(CTFontRef)font
                      extrusionDepth:(CGFloat)extrusionDepth
                    vertexDescriptor:(MDLVertexDescriptor *)vertexDescriptor
                     bufferAllocator:(MTKMeshBufferAllocator *)bufferAllocator
{
    // Create an attributed string from the provided text; we make our own attributed string
    // to ensure that the entire mesh has a single style, which simplifies things greatly.
    NSDictionary *attributes = @{ NSFontAttributeName : (__bridge id)font };
    CFAttributedStringRef attributedString = CFAttributedStringCreate(NULL,
                                                                      (__bridge CFStringRef)string,
                                                                      (__bridge CFDictionaryRef)attributes);
    
    // Transform the attributed string to a linked list of glyphs, each with an associated path from the specified font
    CGRect bounds;
    Glyph *glyphs = [self glyphsForAttributedString:attributedString imageBounds:&bounds];
    
    CFRelease(attributedString);
    
    // Flatten the paths associated with the glyphs so we can more easily tessellate them in the next step
    [self flattenPathsForGlyphs:glyphs];
    
    // Tessellate the glyphs into contours and actual mesh geometry
    [self tessellatePathsForGlyphs:glyphs];
    
    // Figure out how much space we need in our vertex and index buffers to accommodate the mesh
    NSUInteger vertexCount = 0, indexCount = 0;
    [self calculateVertexCount:&vertexCount indexCount:&indexCount forGlyphs:glyphs];
    
    // Allocate the vertex and index buffers
    id<MDLMeshBuffer> vertexBuffer = [bufferAllocator newBuffer:vertexCount * sizeof(MeshVertex)
                                                           type:MDLMeshBufferTypeVertex];
    id<MDLMeshBuffer> indexBuffer = [bufferAllocator newBuffer:indexCount * sizeof(IndexType)
                                                          type:MDLMeshBufferTypeIndex];
    
    // Write text mesh geometry into the vertex and index buffers
    NSUInteger vertexBufferOffset = 0, indexBufferOffset = 0;
    [self writeVerticesForGlyphs:glyphs
                          bounds:bounds
                  extrusionDepth:extrusionDepth
                          buffer:vertexBuffer
                          offset:&vertexBufferOffset];
    
    [self writeIndicesForGlyphs:glyphs
                         buffer:indexBuffer
                         offset:&indexBufferOffset];
    
    GlyphListFree(glyphs);

    // Use ModelIO to create a mesh object, then return a MetalKit mesh we can render later
    MDLSubmesh *submesh = [[MDLSubmesh alloc] initWithIndexBuffer:indexBuffer
                                                       indexCount:indexCount
                                                        indexType:MDLIndexBitDepthUInt32
                                                     geometryType:MDLGeometryTypeTriangles
                                                         material:nil];
    NSArray *submeshes = @[submesh];
    MDLMesh *mdlMesh = [self meshForVertexBuffer:vertexBuffer
                                     vertexCount:vertexCount
                                       submeshes:submeshes
                                vertexDescriptor:vertexDescriptor];

    NSError *error = nil;
    MTKMesh *mesh = [[MTKMesh alloc] initWithMesh:mdlMesh device:bufferAllocator.device error:&error];
    if (error) {
        NSLog(@"Unable to create MTK mesh from MDL mesh");
    }
    return mesh;
}

+ (Glyph *)glyphsForAttributedString:(CFAttributedStringRef)attributedString imageBounds:(CGRect *_Nullable)imageBounds {
    Glyph *head = NULL, *tail = NULL;
    
    // Create a typesetter and use it to lay out a single line of text
    CTTypesetterRef typesetter = CTTypesetterCreateWithAttributedString(attributedString);
    CTLineRef line = CTTypesetterCreateLine(typesetter, CFRangeMake(0, 0));
    NSArray *runs = (__bridge NSArray *)CTLineGetGlyphRuns(line);
    
    // For each of the runs, of which there should only be one...
    for (int runIdx = 0; runIdx < runs.count; ++runIdx) {
        CTRunRef run = (__bridge CTRunRef)runs[runIdx];
        const CFIndex glyphCount = CTRunGetGlyphCount(run);

        // Retrieve the list of glyph positions so we know how to transform the paths we get from the font
        CGPoint *glyphPositions = malloc(sizeof(CGPoint) * glyphCount);
        CTRunGetPositions(run, CFRangeMake(0, 0), glyphPositions);

        // Retrieve the bounds of the text, so we can crudely center it
        CGRect bounds = CTRunGetImageBounds(run, NULL, CFRangeMake(0, 0));
        bounds.origin.x -= bounds.size.width / 2;
        
        CGGlyph *glyphs = malloc(sizeof(CGGlyph) * glyphCount);
        CTRunGetGlyphs(run, CFRangeMake(0, 0), glyphs);
        
        // Fetch the font from the current run. We could have taken this as a parameter, but this is more future-proof.
        NSDictionary *runAttributes = (__bridge NSDictionary *)CTRunGetAttributes(run);
        CTFontRef font = (__bridge CTFontRef)runAttributes[NSFontAttributeName];
        
        // For each glyph in the run...
        for (int glyphIdx = 0; glyphIdx < glyphCount; ++glyphIdx) {
            // Compute a transform that will position the glyph correctly relative to the others, accounting for centering
            CGPoint glyphPosition = glyphPositions[glyphIdx];
            CGAffineTransform glyphTransform = CGAffineTransformMakeTranslation(glyphPosition.x - bounds.size.width / 2,
                                                                                glyphPosition.y);
            
            // Retrieve the actual path for this glyph from the font
            CGPathRef path = CTFontCreatePathForGlyph(font, glyphs[glyphIdx], &glyphTransform);
            
            if (path == NULL) {
                continue; // non-printing and whitespace characters have no associated path
            }
            
            // Add the glyph to the list of glyphs, creating the list if this is the first glyph
            if (head == NULL) {
                head = GlyphCreate();
                tail = head;
            } else {
                tail->next = GlyphCreate();
                tail = tail->next;
            }
            
            tail->path = path;
        }
        
        if (imageBounds) {
            *imageBounds = bounds;
        }

        free(glyphPositions);
        free(glyphs);
    }
    
    CFRelease(typesetter);
    CFRelease(line);
    
    return head;
}

+ (void)flattenPathsForGlyphs:(Glyph *)glyphs {
    Glyph *glyph = glyphs;
    // For each glyph, replace its non-flattened path with a flattened path
    while (glyph) {
        CGPathRef flattenedPath = [self newFlattenedPathForPath:glyph->path flatness:0.1];
        CFRelease(glyph->path);
        glyph->path = flattenedPath;
        
        glyph = glyph->next;
    }
}

+ (CGPathRef)newFlattenedPathForPath:(CGPathRef)path flatness:(CGFloat)flatness {
    CGMutablePathRef flattenedPath = CGPathCreateMutable();
    // Iterate the elements in the path, converting curve segments into sequences of small line segments
    CGPathApplyWithBlock(path, ^(const CGPathElement *element) {
        switch (element->type) {
            case kCGPathElementMoveToPoint: {
                CGPoint point = element->points[0];
                CGPathMoveToPoint(flattenedPath, NULL, point.x, point.y);
                break;
            }
            case kCGPathElementAddLineToPoint: {
                CGPoint point = element->points[0];
                CGPathAddLineToPoint(flattenedPath, NULL, point.x, point.y);
                break;
            }
            case kCGPathElementAddCurveToPoint:
                assert(!"Can't currently flatten font outlines containing cubic curve segments");
                break;
            case kCGPathElementAddQuadCurveToPoint: {
#if USE_ADAPTIVE_SUBDIVISION
                const int MAX_SUBDIVS = 20;
                const CGPoint a = CGPathGetCurrentPoint(flattenedPath); // "from" point
                const CGPoint b = element->points[1]; // "to" point
                const CGPoint c = element->points[0]; // control point
                const CGFloat tolSq = flatness * flatness; // maximum tolerable squared error
                CGFloat t = 0; // Parameter of the curve up to which we've subdivided
                CGFloat candT = 0.5; // "Candidate" parameter of the curve we're currently evaluating
                CGPoint p = a; // Point along curve at parameter t
                while (t < 1.0) {
                    int subdivs = 1;
                    CGFloat err = FLT_MAX; // Squared distance from midpoint of candidate segment to midpoint of true curve segment
                    CGPoint candP = p;
                    candT = fmin(1.0, t + 0.5);
                    while (err > tolSq) {
                        candP = evalQuadCurve(a, b, c, candT);
                        CGFloat midT = (t + candT) / 2;
                        CGPoint midCurve = evalQuadCurve(a, b, c, midT);
                        CGPoint midSeg = lerpPoints(p, candP, 0.5);
                        err = pow(midSeg.x - midCurve.x, 2) + pow(midSeg.y - midCurve.y, 2);
                        if (err > tolSq) {
                            candT = t + 0.5 * (candT - t);
                            if (++subdivs > MAX_SUBDIVS) {
                                break;
                            }
                        }
                    }
                    t = candT;
                    p = candP;
                    CGPathAddLineToPoint(flattenedPath, NULL, p.x, p.y);
                }
#else
                CGPoint a = CGPathGetCurrentPoint(flattenedPath);
                CGPoint b = element->points[1];
                CGPoint c = element->points[0];
                for (int i = 0; i < DEFAULT_QUAD_CURVE_SUBDIVISIONS; ++i) {
                    float t = (float)i / (DEFAULT_QUAD_CURVE_SUBDIVISIONS - 1);
                    CGPoint r = evalQuadCurve(a, b, c, t);
                    CGPathAddLineToPoint(flattenedPath, NULL, r.x, r.y);
                }
#endif
                break;
            }
            case kCGPathElementCloseSubpath:
                CGPathCloseSubpath(flattenedPath);
                break;
        }
    });
    return flattenedPath;
}

+ (void)tessellatePathsForGlyphs:(Glyph *)glyphs {
    // Create a new libtess tessellator, requesting constrained Delaunay triangulation
    TESStesselator *tess = tessNewTess(NULL);
    tessSetOption(tess, TESS_CONSTRAINED_DELAUNAY_TRIANGULATION, 1);
    
    const int polygonIndexCount = 3; // triangles only
    
    Glyph *glyph = glyphs;
    while (glyph) {
        // Accumulate the contours of the flattened path into the tessellator so it can compute the CDT
        PathContour *contours = [self tessellatePath:glyph->path usingTessellator:tess];

        // Do the actual tessellation work
        int result = tessTesselate(tess, TESS_WINDING_ODD, TESS_POLYGONS, polygonIndexCount, VERT_COMPONENT_COUNT, NULL);
        if (!result) {
            NSLog(@"Unable to tessellate path");
        }
        
        // Retrieve the tessellated mesh from the tessellator and copy the contour list and geometry to the current glyph
        int vertexCount = tessGetVertexCount(tess);
        const TESSreal *vertices = tessGetVertices(tess);
        int indexCount = tessGetElementCount(tess) * polygonIndexCount;
        const TESSindex *indices = tessGetElements(tess);
        
        glyph->contours = contours;
        
        GlyphSetGeometry(glyph, vertexCount, vertices, indexCount, indices);
        
        glyph = glyph->next;
    }
    
    tessDeleteTess(tess);
}

+ (PathContour *)tessellatePath:(CGPathRef)path usingTessellator:(TESStesselator *)tessellator {
    __block PathContour *contour = PathContourCreate();
    PathContour *contours = contour;
    // Iterate the line segments in the flattened path, accumulating each subpath as a contour,
    // then pass closed contours to the tessellator
    CGPathApplyWithBlock(path, ^(const CGPathElement *element){
        switch (element->type) {
            case kCGPathElementMoveToPoint: {
                CGPoint point = element->points[0];
                if (PathContourGetVertexCount(contour) != 0) {
                    NSLog(@"Open subpaths are not supported; all contours must be closed");
                }
                PathContourAddVertex(contour, PathVertexMake(point.x, point.y));
                break;
            }
            case kCGPathElementAddLineToPoint: {
                CGPoint point = element->points[0];
                PathContourAddVertex(contour, PathVertexMake(point.x, point.y));
                break;
            }
            case kCGPathElementAddCurveToPoint:
            case kCGPathElementAddQuadCurveToPoint:
                assert(!"Tessellator does not expect curve segments; flatten path first");
                break;
            case kCGPathElementCloseSubpath: {
                PathVertex *vertices = PathContourGetVertices(contour);
                int vertexCount = PathContourGetVertexCount(contour);
                tessAddContour(tessellator, 2, vertices, sizeof(PathVertex), vertexCount);
                contour->next = PathContourCreate();
                contour = contour->next;
                break;
            }
        }
    });
    return contours;
}

+ (void)calculateVertexCount:(NSUInteger *)vertexBufferCount
                  indexCount:(NSUInteger *)indexBufferCount
                   forGlyphs:(Glyph *)glyphs
{
    *vertexBufferCount = 0;
    *indexBufferCount = 0;
    
    Glyph *glyph = glyphs;
    while (glyph) {
        // Space for front- and back-facing tessellated faces
        *vertexBufferCount += 2 * glyph->vertexCount;
        *indexBufferCount += 2 * glyph->indexCount;
        
        PathContour *contour = glyph->contours;
        // Space for stitching faces
        while (contour) {
            *vertexBufferCount += 2 * contour->vertexCount;
            *indexBufferCount += 6 * (contour->vertexCount + 1);
            contour = contour->next;
        }
        glyph = glyph->next;
    }
}

+ (void)writeVerticesForGlyphs:(Glyph *)glyphs
                        bounds:(CGRect)bounds
                extrusionDepth:(CGFloat)extrusionDepth
                    buffer:(id<MDLMeshBuffer>)vertexBuffer
                        offset:(NSUInteger *)offset
{
    MDLMeshBufferMap *map = [vertexBuffer map];
    
    // For each glyph, write two copies of the tessellated mesh into the vertex buffer,
    // one after the other. The first copy is for front-facing faces, and the second
    // copy is for rear-facing faces
    Glyph *glyph = glyphs;
    while (glyph) {
        MeshVertex *vertices = (MeshVertex *)(map.bytes + *offset);

        for (size_t i = 0, j = glyph->vertexCount; i < glyph->vertexCount; ++i, ++j) {
            float x = glyph->vertices[i * VERT_COMPONENT_COUNT + 0];
            float y = glyph->vertices[i * VERT_COMPONENT_COUNT + 1];
            float s = remap(CGRectGetMinX(bounds), CGRectGetMaxX(bounds), 0, 1, x);
            float t = remap(CGRectGetMinY(bounds), CGRectGetMaxY(bounds), 1, 0, y);

            vertices[i].x = x;
            vertices[i].y = y;
            vertices[i].z = 0;
            vertices[i].s = s;
            vertices[i].t = t;

            vertices[j].x = x;
            vertices[j].y = y;
            vertices[j].z = -extrusionDepth;
            vertices[j].s = s;
            vertices[j].t = t;
        }
        
        *offset += glyph->vertexCount * 2 * sizeof(MeshVertex);
        glyph = glyph->next;
    }

    // Now, write two copies of the contour vertices into the vertex buffer. The first
    // set correspond to the front-facing faces, and the second copy correspond to the
    // rear-facing faces
    glyph = glyphs;
    while (glyph) {
        PathContour *contour = glyph->contours;
        while (contour) {
            MeshVertex *vertices = (MeshVertex *)(map.bytes + *offset);

            for (int i = 0, j = contour->vertexCount; i < contour->vertexCount; ++i, ++j) {
                float x = contour->vertices[i].x;
                float y = contour->vertices[i].y;

                float s = remap(CGRectGetMinX(bounds), CGRectGetMaxX(bounds), 0, 1, x);
                float t = remap(CGRectGetMinY(bounds), CGRectGetMaxY(bounds), 1, 0, y);

                vertices[i].x = x;
                vertices[i].y = y;
                vertices[i].z = 0;
                vertices[i].s = s;
                vertices[i].t = t;

                vertices[j].x = x;
                vertices[j].y = y;
                vertices[j].z = -extrusionDepth;
                vertices[j].s = s;
                vertices[j].t = t;
            }

            *offset += contour->vertexCount * 2 * sizeof(MeshVertex);

            contour = contour->next;
        }

        glyph = glyph->next;
    }
}

+ (void)writeIndicesForGlyphs:(Glyph *)glyphs buffer:(id<MDLMeshBuffer>)indexBuffer offset:(NSUInteger *)offset {
    MDLMeshBufferMap *indexMap = [indexBuffer map];
    
    // Write indices for front-facing and back-facing faces
    Glyph *glyph = glyphs;
    UInt32 baseVertex = 0;
    while (glyph) {
        IndexType *indices = (IndexType *)(indexMap.bytes + *offset);

        for (size_t i = 0, j = glyph->indexCount; i < glyph->indexCount; i += 3, j += 3) {
            // front face
            indices[i + 2] = glyph->indices[i + 0] + baseVertex;
            indices[i + 1] = glyph->indices[i + 1] + baseVertex;
            indices[i + 0] = glyph->indices[i + 2] + baseVertex;
            // rear face
            indices[j + 0] = glyph->indices[i + 0] + baseVertex + glyph->vertexCount;
            indices[j + 1] = glyph->indices[i + 1] + baseVertex + glyph->vertexCount;
            indices[j + 2] = glyph->indices[i + 2] + baseVertex + glyph->vertexCount;
        }
        
        *offset += glyph->indexCount * 2 * sizeof(IndexType);
        
        baseVertex += glyph->vertexCount * 2;
        
        glyph = glyph->next;
    }
    
    // Write indices for stitching faces
    glyph = glyphs;
    while (glyph) {
        PathContour *contour = glyph->contours;
        while (contour) {
            IndexType *indices = (IndexType *)(indexMap.bytes + *offset);
            
            for (int i = 0; i < contour->vertexCount; ++i) {
                int i0 = i;
                int i1 = (i + 1) % contour->vertexCount;
                int i2 = i + contour->vertexCount;
                int i3 = (i + 1) % contour->vertexCount + contour->vertexCount;
                
                indices[i * 6 + 0] = i0 + baseVertex;
                indices[i * 6 + 1] = i1 + baseVertex;
                indices[i * 6 + 2] = i2 + baseVertex;
                indices[i * 6 + 3] = i1 + baseVertex;
                indices[i * 6 + 4] = i3 + baseVertex;
                indices[i * 6 + 5] = i2 + baseVertex;
            }
            
            baseVertex += contour->vertexCount * 2;

            *offset += contour->vertexCount * 6 * sizeof(IndexType);

            contour = contour->next;
        }
        
        glyph = glyph->next;
    }
}

+ (MDLMesh *)meshForVertexBuffer:(id<MDLMeshBuffer>)vertexBuffer
                     vertexCount:(NSUInteger)vertexCount
                       submeshes:(NSArray<MDLSubmesh *> *)submeshes
                vertexDescriptor:(MDLVertexDescriptor *)vertexDescriptor
{
    MDLMesh *mdlMesh = [[MDLMesh alloc] initWithVertexBuffer:vertexBuffer
                                                 vertexCount:vertexCount
                                                  descriptor:vertexDescriptor
                                                   submeshes:submeshes];
    
    [mdlMesh addNormalsWithAttributeNamed:MDLVertexAttributeNormal creaseThreshold:sqrt(2)/2];
    
    return mdlMesh;
}

@end
