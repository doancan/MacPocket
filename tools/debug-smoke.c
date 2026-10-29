#include <stdio.h>
#include <unistd.h>

__attribute__((noinline)) int macpocket_add(int left, int right) {
    return left + right;
}

int main(int argc, char **argv) {
    (void)argv;
    volatile int result = macpocket_add(20, 22);
    if (argc == 1) {
        printf("MacPocket debugger smoke test: %d\n", result);
        fflush(stdout);
    }
    usleep(500000);
    return result == 42 ? 0 : 1;
}
