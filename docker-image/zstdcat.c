#include <stdio.h>
#include <stdlib.h>

typedef struct ZSTD_DStream_s ZSTD_DStream;
typedef struct { const void *src; size_t size; size_t pos; } ZSTD_inBuffer;
typedef struct { void *dst; size_t size; size_t pos; } ZSTD_outBuffer;

extern ZSTD_DStream *ZSTD_createDStream(void);
extern size_t ZSTD_freeDStream(ZSTD_DStream *zds);
extern size_t ZSTD_initDStream(ZSTD_DStream *zds);
extern size_t ZSTD_decompressStream(ZSTD_DStream *zds, ZSTD_outBuffer *output, ZSTD_inBuffer *input);
extern unsigned ZSTD_isError(size_t code);
extern const char *ZSTD_getErrorName(size_t code);

int main(void) {
    unsigned char in[1 << 20], out[1 << 20];
    ZSTD_DStream *stream = ZSTD_createDStream();
    if (!stream || ZSTD_isError(ZSTD_initDStream(stream))) return 1;
    size_t n;
    while ((n = fread(in, 1, sizeof(in), stdin)) != 0) {
        ZSTD_inBuffer input = {in, n, 0};
        while (input.pos < input.size) {
            ZSTD_outBuffer output = {out, sizeof(out), 0};
            size_t status = ZSTD_decompressStream(stream, &output, &input);
            if (ZSTD_isError(status)) {
                fprintf(stderr, "%s\n", ZSTD_getErrorName(status));
                return 1;
            }
            if (fwrite(out, 1, output.pos, stdout) != output.pos) return 1;
        }
    }
    if (ferror(stdin) || fflush(stdout)) return 1;
    ZSTD_freeDStream(stream);
    return 0;
}
