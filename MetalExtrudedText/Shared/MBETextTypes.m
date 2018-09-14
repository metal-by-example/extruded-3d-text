
#import "MBETextTypes.h"

PathVertex PathVertexMake(float x, float y) {
    PathVertex v;
    v.x = x;
    v.y = y;
    return v;
}

PathContour *_Nonnull PathContourCreate() {
    PathContour *contour = (PathContour *)malloc(sizeof(PathContour));
    contour->capacity = 32;
    contour->vertexCount = 0;
    contour->vertices = (PathVertex *)malloc(contour->capacity * sizeof(PathVertex));
    contour->next = NULL;
    return contour;
}

void PathContourAddVertex(PathContour *contour, PathVertex v) {
    int i = contour->vertexCount;
    if (i >= contour->capacity - 1) {
        PathVertex *old = contour->vertices;
        contour->capacity *= 1.61; // Engineering approximation to the golden ratio
        contour->vertices = (PathVertex *)malloc(contour->capacity * sizeof(PathVertex));
        memcpy(contour->vertices, old, contour->vertexCount * sizeof(PathVertex));
        free(old);
    }
    contour->vertices[i] = v;
    contour->vertexCount++;
}

int PathContourGetVertexCount(PathContour *contour) {
    return contour->vertexCount;
}

PathVertex *PathContourGetVertices(PathContour *contour) {
    return contour->vertices;
}

void PathContourListFree(PathContour *_Nullable contour) {
    if (contour) {
        if (contour->next) {
            PathContourListFree(contour->next);
        }
        free(contour->vertices);
        free(contour);
    }
}

Glyph *GlyphCreate() {
    Glyph *glyph = (Glyph *)malloc(sizeof(Glyph));
    bzero(glyph, sizeof(Glyph));
    return glyph;
}

void GlyphListFree(Glyph *glyph) {
    if (glyph) {
        if (glyph->next) {
            GlyphListFree(glyph->next);
        }
        PathContourListFree(glyph->contours);
        CFRelease(glyph->path);
        free(glyph->vertices);
        free(glyph->indices);
        free(glyph);
    }
}

void GlyphSetGeometry(Glyph *glyph,
                      size_t vertexCount, const TESSreal *vertices,
                      size_t indexCount, const TESSindex *indices)
{
    free(glyph->vertices);
    free(glyph->indices);
    
    glyph->vertexCount = (UInt32)vertexCount;
    size_t vertexByteCount = vertexCount * VERT_COMPONENT_COUNT * sizeof(TESSreal);
    glyph->vertices = malloc(vertexByteCount);
    memcpy(glyph->vertices, vertices, vertexByteCount);
    
    glyph->indexCount = (UInt32)indexCount;
    size_t indexByteCount = indexCount * sizeof(TESSindex);
    glyph->indices = malloc(indexByteCount);
    memcpy(glyph->indices, indices, indexByteCount);
}
