// app_debug.c
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

// your existing AXI-Lite control/status offsets
#define ADDR_START_CTRL 0x00
#define ADDR_STATUS     0x04

// ——— debug offsets (must match your rebuilt RTL) ———
#define DBG_START         0x30
#define DBG_ADDRA_LSB     0x31
#define DBG_ADDRA_MSB     0x32
#define DBG_ADDRB_LSB     0x33
#define DBG_ADDRB_MSB     0x34
#define DBG_ADDRC_LSB     0x35
#define DBG_ADDRC_MSB     0x36
#define DBG_BUF_INDEX     0x37
#define DBG_BUF_DATA_LSB  0x38
#define DBG_BUF_DATA_MSB  0x39

static void check_rw(ssize_t rc, const char *what, ssize_t expected) {
    if (rc < 0) {
        perror(what);
        exit(1);
    }
    if (expected>=0 && rc != expected) {
        fprintf(stderr, "%s: got %zd, expected %zd\n", what, rc, expected);
        exit(1);
    }
}

int main(int argc, char *argv[])
{
    int8_t  data[256]       = {0};
    int8_t  temp_array[256] = {0};
    const int length        = 256;
    int     fd;
    uint32_t matrix_a = 0xBE000000,
             matrix_b = 0xBE100000,
             matrix_c = 0xBE200000;
    uint32_t tmp     = 0;

    printf("DVCon Accelerator App (with debug)\n");
    fd = open("/dev/accelerator_test", O_RDWR);
    if (fd < 0) {
        perror("open");
        return 1;
    }

    for (int k = 1; k <= 10; k++) {
        // — your unchanged setup —
        for (int i = 0; i < length; i++)
            data[i] = (int8_t)k;
        printf("Data: %d\n", k);

        // halt & sync
        check_rw(pwrite(fd, &tmp, 4, ADDR_START_CTRL), "pwrite halt", 4);
        check_rw(pread (fd, &tmp, 4, ADDR_STATUS),     "pread sync",  4);

        // upload A, B
        check_rw(pwrite(fd, data,   length, matrix_a), "pwrite A", length);
        check_rw(pwrite(fd, data,   length, matrix_b), "pwrite B", length);

        // set base-addrs
        check_rw(pwrite(fd, &matrix_a, 4, 0x10), "pwrite A LSB", 4);
        tmp = 0; check_rw(pwrite(fd, &tmp,      4, 0x14), "pwrite A MSB", 4);
        check_rw(pwrite(fd, &matrix_b, 4, 0x18), "pwrite B LSB", 4);
        tmp = 0; check_rw(pwrite(fd, &tmp,      4, 0x1C), "pwrite B MSB", 4);
        check_rw(pwrite(fd, &matrix_c, 4, 0x20), "pwrite C LSB", 4);
        tmp = 0; check_rw(pwrite(fd, &tmp,      4, 0x24), "pwrite C MSB", 4);

        // — start pulse —
        tmp = 1;
        check_rw(pwrite(fd, &tmp, 4, ADDR_START_CTRL), "pwrite start", 4);

        // === DEBUG READS ===
        {
          uint32_t lo, hi, idx;

          // 1) start_pulse
          check_rw(pread(fd, &tmp, 4, DBG_START), "pread DBG_START", 4);
          printf("[DEBUG] start_pulse = %u\n", tmp & 1);

          // 2) addr_a_reg
          check_rw(pread(fd, &lo, 4, DBG_ADDRA_LSB), "pread ADDRA_LSB", 4);
          check_rw(pread(fd, &hi, 4, DBG_ADDRA_MSB), "pread ADDRA_MSB", 4);
          printf("[DEBUG] addr_a_reg = 0x%08x%08x\n", hi, lo);

          // 3) addr_b_reg
          check_rw(pread(fd, &lo, 4, DBG_ADDRB_LSB), "pread ADDRB_LSB", 4);
          check_rw(pread(fd, &hi, 4, DBG_ADDRB_MSB), "pread ADDRB_MSB", 4);
          printf("[DEBUG] addr_b_reg = 0x%08x%08x\n", hi, lo);

          // 4) addr_c_reg
          check_rw(pread(fd, &lo, 4, DBG_ADDRC_LSB), "pread ADDRC_LSB", 4);
          check_rw(pread(fd, &hi, 4, DBG_ADDRC_MSB), "pread ADDRC_MSB", 4);
          printf("[DEBUG] addr_c_reg = 0x%08x%08x\n", hi, lo);

          // 5) buffer_A[0]
          idx = 0;
          check_rw(pwrite(fd, &idx, 4, DBG_BUF_INDEX),   "pwrite BUF_IDX",   4);
          check_rw(pread(fd, &lo, 4, DBG_BUF_DATA_LSB),  "pread BUF_DAT_LSB", 4);
          check_rw(pread(fd, &hi, 4, DBG_BUF_DATA_MSB),  "pread BUF_DAT_MSB", 4);
          printf("[DEBUG] buffer_A[0] = 0x%08x%08x\n", hi, lo);
        }

        // — your unchanged poll & print —
        while (1) {
            check_rw(pread(fd, &tmp, 4, ADDR_STATUS), "pread status", 4);
            if (tmp & 0x2) {
                printf("Result Generated\n");
                break;
            }
        }
        printf("Result Matrix\n");
        check_rw(pread(fd, temp_array, 10, matrix_c), "pread result", 10);
        for (int i = 0; i < 10; i++)
            printf("%d ", temp_array[i]);
        printf("\n\n");

        tmp = 0;
        check_rw(pwrite(fd, &tmp, 4, ADDR_START_CTRL), "pwrite halt2", 4);
    }

    close(fd);
    return 0;
}
