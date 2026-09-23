#ifndef MACOS_WINDOW_H
#define MACOS_WINDOW_H

#ifdef __cplusplus
extern "C" {
#endif

void macos_start_watching(void);
void macos_lock_video_window(int width, int height);
void macos_reapply_video_window(void);
void macos_set_waiting(int waiting);

int macos_video_bridge_enabled(void);
void macos_video_bridge_start(void);
void macos_video_bridge_send_size(int width, int height);
void macos_video_bridge_send_packet(const unsigned char *data, int length, unsigned long long pts, int codec);
void macos_video_bridge_send_end(void);

#ifdef __cplusplus
}
#endif

#endif
