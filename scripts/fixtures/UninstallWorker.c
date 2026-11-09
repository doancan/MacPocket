#include <signal.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc > 1) signal(SIGTERM, SIG_IGN);
    for (;;) pause();
}
