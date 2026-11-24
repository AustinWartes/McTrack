#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct { int32_t id; float decision_margin; float translation[3]; float rotation[9]; float corners[8]; } MCTagPose;
void *mc_tag_create(void);
void mc_tag_destroy(void *detector);
// Input is the full-resolution, unrotated ARKit Y plane. Returns number of poses written.
int mc_tag_detect(void *detector, const uint8_t *y, int width, int height, int stride,
                  double fx, double fy, double cx, double cy, double tag_size,
                  MCTagPose *out, int capacity);
#ifdef __cplusplus
}
#endif
