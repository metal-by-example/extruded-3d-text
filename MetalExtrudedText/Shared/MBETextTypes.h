
#import <QuartzCore/QuartzCore.h>
#include "tesselator.h"

#define VERT_COMPONENT_COUNT 2 // 2D vertices (x, y)

/// A mesh vertex containing a position, normal, and texture coordinates
typedef struct MeshVertex {
    float x, y, z;
    float nx, ny, nz;
    float s, t;
} MeshVertex;

/// A 2D point on a planar path
typedef struct {
    float x, y;
} PathVertex;

PathVertex PathVertexMake(float x, float y);

/// A linked list of closed path contours, each specified as a list of points
typedef struct PathContour {
    PathVertex *vertices;
    int vertexCount;
    int capacity;
    struct PathContour *next;
} PathContour;

/// Create a new path contour
PathContour *_Nonnull PathContourCreate(void);

/// Add a vertex to the specified contour
void PathContourAddVertex(PathContour *contour, PathVertex v);

/// Get the number of vertices in this contour
int PathContourGetVertexCount(PathContour *contour);

/// Get the list of vertices that comprise this contour
PathVertex *PathContourGetVertices(PathContour *contour);

/// Free the list of path contours rooted at the provided contour
void PathContourListFree(PathContour *_Nullable contour);

/// A linked list of glyphs, each jointly represented as a list of contours, a CGPath, and a set of vertices and indices
typedef struct Glyph {
    CGPathRef path;
    
    PathContour *contours;
    
    UInt32 vertexCount;
    TESSreal *vertices;
    UInt32 indexCount;
    TESSindex *indices;
    
    struct Glyph *next;
} Glyph;

/// Create a new glyph
Glyph *GlyphCreate(void);

/// Copy the provided mesh data into the glyph; glyph does not strongly reference provided pointers
void GlyphSetGeometry(Glyph *glyph,
                      size_t vertexCount, const TESSreal *vertices,
                      size_t indexCount, const TESSindex *indices);

/// Free a linked list of glyphs
void GlyphListFree(Glyph *glyph);
