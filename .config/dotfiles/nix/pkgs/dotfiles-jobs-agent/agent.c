// dotfiles-jobs-agent <harness> <interval-seconds> <unlock-notification>
// The dotfiles jobs job's program, which launchd keeps alive. nix-darwin builds it (default.nix
// beside this file, wired in nix/darwin.nix). It runs
//     /bin/zsh <harness> jobs tick --trigger <tag>
// once at start (load), on every <unlock-notification> from the distributed notification
// center (screenIsUnlocked), every <interval-seconds> (tick), and on SIGUSR1 (screenIsUnlocked
// again, so `dotfiles jobs unlock` can simulate an unlock). Runs are serialized: an event that
// arrives during a run is delivered after it. A timer missed asleep fires once on wake.
#include <CoreFoundation/CoreFoundation.h>
#include <dispatch/dispatch.h>
#include <errno.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
static const char *g_harness;

static void run(const char *tag) {
    char *argv[] = {"/bin/zsh", (char *)g_harness, "jobs", "tick", "--trigger", (char *)tag, NULL};
    pid_t pid;
    int rc = posix_spawn(&pid, "/bin/zsh", NULL, NULL, argv, environ);
    if (rc != 0) {
        fprintf(stderr, "dotfiles-jobs-agent: spawn failed: %s\n", strerror(rc));
        return;
    }
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {
    }
}

static void on_unlock(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef ui) {
    (void)c; (void)o; (void)n; (void)obj; (void)ui;
    run("screenIsUnlocked");
}

static void on_timer(CFRunLoopTimerRef t, void *info) {
    (void)t; (void)info;
    run("tick");
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <harness> <interval-seconds> <unlock-notification>\n", argv[0]);
        return 2;
    }
    g_harness = argv[1];
    double interval = atof(argv[2]);
    if (interval < 1) {
        interval = 300;
    }
    CFStringRef name = CFStringCreateWithCString(NULL, argv[3], kCFStringEncodingUTF8);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDistributedCenter(), NULL, on_unlock, name, NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent() + interval, interval, 0, 0, on_timer, NULL);
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopDefaultMode);
    // SIGUSR1 simulates an unlock; the handler runs on the main queue, which the run loop drains.
    signal(SIGUSR1, SIG_IGN);
    dispatch_source_t usr1 = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGUSR1, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(usr1, ^{ run("screenIsUnlocked"); });
    dispatch_resume(usr1);
    run("load");
    CFRunLoopRun();
    return 0;
}
