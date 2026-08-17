// Stub canvas for PC build — all drawing methods are no-ops
#ifndef __CANVAS_H__
#define __CANVAS_H__

struct StubCanvas {
    void DrawDot(const char*, const char*, int, int) {}
    void DrawLine(const char*, const char*, int, int, int, int) {}
    void DrawText(const char*, const char*, int, int, const char*) {}
    void DrawImage(const char*, const char*, int, int, unsigned char*, int) {}
};

static StubCanvas __canvas;

#endif
