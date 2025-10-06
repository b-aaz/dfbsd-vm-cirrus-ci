#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>

int main(int argc, char ** argv) {

    char *sstr = argv[1];
    size_t ssl = strlen(sstr);
    size_t idx = 0;
    char c;

    if (argc != 2) {
        return 2;
    }

    signal(SIGPIPE,SIG_IGN);
    while (read(STDIN_FILENO, &c, 1) > 0) {
        if (c == sstr[idx]) {
            idx++;
            if (idx == ssl) {
		    exit(0);
            }
        } else {
            idx = (c == sstr[0]) ? 1 : 0;
        }
    }
    exit(1);
}
