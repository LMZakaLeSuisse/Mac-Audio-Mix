#include <arpa/inet.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static long file_size(FILE *file) {
    if (fseek(file, 0, SEEK_END) != 0) return -1;
    long size = ftell(file);
    rewind(file);
    return size;
}

int main(int argc, char **argv) {
    if (argc < 4 || argc % 2 != 0) {
        fprintf(stderr, "usage: %s output.icns type png [type png ...]\n", argv[0]);
        return 1;
    }

    FILE *output = fopen(argv[1], "wb+");
    if (!output) return 2;
    fwrite("icns", 1, 4, output);
    uint32_t total = 0;
    fwrite(&total, sizeof(total), 1, output);

    for (int i = 2; i < argc; i += 2) {
        if (strlen(argv[i]) != 4) return 3;
        FILE *input = fopen(argv[i + 1], "rb");
        if (!input) return 4;
        long size = file_size(input);
        if (size < 0) return 5;

        fwrite(argv[i], 1, 4, output);
        uint32_t chunk_size = htonl((uint32_t)size + 8);
        fwrite(&chunk_size, sizeof(chunk_size), 1, output);

        unsigned char buffer[16384];
        size_t count;
        while ((count = fread(buffer, 1, sizeof(buffer), input)) > 0) {
            fwrite(buffer, 1, count, output);
        }
        fclose(input);
    }

    long final_size = ftell(output);
    total = htonl((uint32_t)final_size);
    fseek(output, 4, SEEK_SET);
    fwrite(&total, sizeof(total), 1, output);
    fclose(output);
    return 0;
}
