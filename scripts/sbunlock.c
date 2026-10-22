#include <notify.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc > 2 && strcmp(argv[1], "--url") == 0) {
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
    } else {
        uint32_t status = notify_post("org.legacy.itg.unlock");
        printf("[+] Posted org.legacy.itg.unlock (status: %u)\n", status);
    }
    return 0;
}
