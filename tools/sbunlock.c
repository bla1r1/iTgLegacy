#include <notify.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

int main(int argc, char **argv) {
    if (argc > 2 && strcmp(argv[1], "--cmd") == 0) {
        FILE *f = fopen("/tmp/itg_cmd.txt", "w");
        if (f) {
            fprintf(f, "%s\n", argv[2]);
            fclose(f);
            chmod("/tmp/itg_cmd.txt", 0666);
        }
        uint32_t status = notify_post("org.legacy.itg.cmd");
        printf("[+] Wrote cmd '%s' and posted org.legacy.itg.cmd (status: %u)\n", argv[2], status);
    } else if (argc > 2 && strcmp(argv[1], "--url") == 0) {
        FILE *f = fopen("/tmp/itg_url.txt", "w");
        if (f) {
            fprintf(f, "%s\n", argv[2]);
            fclose(f);
        }
        uint32_t status = notify_post("org.legacy.itg.launch");
        printf("[+] Wrote url '%s' and posted org.legacy.itg.launch (status: %u)\n", argv[2], status);
    } else if (argc > 1 && strcmp(argv[1], "--launch") == 0) {
        uint32_t status = notify_post("org.legacy.itg.launch");
        printf("[+] Posted org.legacy.itg.launch (status: %u)\n", status);
    } else if (argc > 1 && strcmp(argv[1], "--screenshot") == 0) {
        uint32_t status = notify_post("org.legacy.itg.screenshot");
        printf("[+] Posted org.legacy.itg.screenshot (status: %u)\n", status);
    } else if (argc > 1 && strcmp(argv[1], "--record") == 0) {
        int duration = (argc > 2) ? atoi(argv[2]) : 5;
        int fps = (argc > 3) ? atoi(argv[3]) : 10;
        FILE *f = fopen("/tmp/cap_cfg.txt", "w");
        if (f) {
            fprintf(f, "%d %d\n", fps, duration);
            fclose(f);
        }
        uint32_t status = notify_post("org.legacy.itg.record_start");
        printf("[+] Recording started for %d s at %d fps (status: %u)\n", duration, fps, status);
    } else if (argc > 1 && strcmp(argv[1], "--record-stop") == 0) {
        uint32_t status = notify_post("org.legacy.itg.record_stop");
        printf("[+] Recording stopped (status: %u)\n", status);
    } else {
        uint32_t status = notify_post("org.legacy.itg.unlock");
        printf("[+] Posted org.legacy.itg.unlock (status: %u)\n", status);
    }
    return 0;
}
