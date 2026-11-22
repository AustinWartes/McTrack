#include "TagBridge.h"
#include "apriltag.h"
#include "apriltag_pose.h"
#include "tagStandard41h12.h"
#include <stdlib.h>
#include <string.h>
typedef struct { apriltag_detector_t *det; apriltag_family_t *fam; } mc_detector;
void *mc_tag_create(void) {
    mc_detector *ctx = calloc(1, sizeof(*ctx));
    if (!ctx) return NULL;
    ctx->fam = tagStandard41h12_create();
    ctx->det = apriltag_detector_create();
    if (!ctx->fam || !ctx->det) { mc_tag_destroy(ctx); return NULL; }
    apriltag_detector_add_family(ctx->det, ctx->fam);
    ctx->det->quad_decimate = 2.0;
    ctx->det->quad_sigma = 0.0;
    ctx->det->nthreads = 2;
    ctx->det->refine_edges = 1;
    return ctx;
}
void mc_tag_destroy(void *opaque) {
    mc_detector *ctx = opaque;
    if (!ctx) return;
    if (ctx->det) apriltag_detector_destroy(ctx->det);
    if (ctx->fam) tagStandard41h12_destroy(ctx->fam);
    free(ctx);
}
int mc_tag_detect(void *opaque, const uint8_t *y, int width, int height, int stride,
                  double fx, double fy, double cx, double cy, double tag_size,
                  MCTagPose *out, int capacity) {
    mc_detector *ctx = opaque;
    if (!ctx || !y || !out || capacity <= 0 || stride < width) return 0;
    image_u8_t image = { .width = width, .height = height, .stride = stride, .buf = (uint8_t *)y };
    zarray_t *detections = apriltag_detector_detect(ctx->det, &image);
    int count = 0;
    for (int i = 0; i < zarray_size(detections) && count < capacity; i++) {
        apriltag_detection_t *d;
        zarray_get(detections, i, &d);
        // Keep successfully decoded detections; retain decision margin for later quality assessment.
        // No additional hardcoded confidence cutoff.
        apriltag_detection_info_t info = { .det = d, .tagsize = tag_size,
            .fx = fx, .fy = fy, .cx = cx, .cy = cy };
        apriltag_pose_t pose;
        double error = estimate_tag_pose(&info, &pose);
        if (error < 0 || !pose.R || !pose.t) continue;
        MCTagPose *p = &out[count++];
        p->id = d->id;
        p->decision_margin = (float)d->decision_margin;
        for (int j = 0; j < 3; j++) {
            p->translation[j] = (float)MATD_EL(pose.t, j, 0);
            for (int k = 0; k < 3; k++) p->rotation[j * 3 + k] = (float)MATD_EL(pose.R, j, k);
        }
        matd_destroy(pose.R);
        matd_destroy(pose.t);
    }
    apriltag_detections_destroy(detections);
    return count;
}
