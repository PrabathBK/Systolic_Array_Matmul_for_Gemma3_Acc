// app.c — GEMMA3 INT8 bring-up against updated RTL
// Build: gcc -O2 -Wall app.c -o app_64

#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>

#define DIE(...) do { fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); exit(1); } while(0)

enum { MATRIX_SIZE = 16, NUM_ELEMS = MATRIX_SIZE * MATRIX_SIZE };

// ---- SoC map (adjust if your address map differs)
#define ACC_BASE_PHYS   0x20060000UL
#define ACC_MAP_SIZE    0x1000

#define DDR_BASE_PHYS   0xBE000000UL
#define DDR_MAP_SIZE    0x00300000UL  // 3 MiB window (enough for A/B/C)

#define A_PHYS (DDR_BASE_PHYS + 0x000000)
#define B_PHYS (DDR_BASE_PHYS + 0x010000)
#define C_PHYS (DDR_BASE_PHYS + 0x020000)

// ---- Accelerator regs (32-bit)
#define REG32(off)      (*(volatile uint32_t*)((uint8_t*)regs + (off)))

#define REG_CTRL        0x00  // write bit0=1 to start; read: [1]=busy,[0]=done
#define REG_STATUS      0x00  // same address (read)
#define REG_A_LSB       0x10
#define REG_A_MSB       0x14
#define REG_B_LSB       0x1C
#define REG_B_MSB       0x20
#define REG_C_LSB       0x28
#define REG_C_MSB       0x2C

// Optional tiny debug window if you want it:
// #define REG_DBG_IDX   0x30
// #define REG_DBG_LS    0x34
// #define REG_DBG_MS    0x38

static void* map_phys(int fd, off_t phys, size_t len) {
    size_t page = sysconf(_SC_PAGESIZE);
    off_t   base = phys & ~(page - 1);
    off_t   delta = phys - base;
    void* p = mmap(NULL, len + delta, PROT_READ|PROT_WRITE, MAP_SHARED, fd, base);
    if (p == MAP_FAILED) return NULL;
    return (uint8_t*)p + delta;
}

static inline void mmio_write64_addr(volatile void* regs, uint64_t a_lsb_msb[2], uint64_t phys)
{
    (void)a_lsb_msb;
    (void)phys;
}

int main(void) {
    printf("=== GEMMA3 16x16 INT8 (AXI-Lite 32-bit) ===\n");

    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) DIE("open(/dev/mem): %s", strerror(errno));

    // Map regs + DDR
    void* regs = map_phys(fd, ACC_BASE_PHYS, ACC_MAP_SIZE);
    if (!regs) DIE("mmap regs @0x%lx: %s", (unsigned long)ACC_BASE_PHYS, strerror(errno));

    void* ddr  = map_phys(fd, DDR_BASE_PHYS, DDR_MAP_SIZE);
    if (!ddr) DIE("mmap ddr  @0x%lx: %s", (unsigned long)DDR_BASE_PHYS, strerror(errno));

    printf("DDR_BASE=0x%08lx SIZE=0x%06x\n", (unsigned long)DDR_BASE_PHYS, DDR_MAP_SIZE);
    printf("Regs @%p, DDR @%p\n", regs, ddr);

    // Host pointers (virtual) into the DDR mapping
    volatile int8_t*  A = (volatile int8_t*)((uint8_t*)ddr + (A_PHYS - DDR_BASE_PHYS));
    volatile int8_t*  B = (volatile int8_t*)((uint8_t*)ddr + (B_PHYS - DDR_BASE_PHYS));
    volatile int32_t* C = (volatile int32_t*)((uint8_t*)ddr + (C_PHYS - DDR_BASE_PHYS));

    // Prime A (pattern), B (identity), clear C
    for (int i = 0; i < NUM_ELEMS; i++) A[i] = (int8_t)((i*3) & 0x7F); // small pattern
    for (int r = 0; r < MATRIX_SIZE; r++)
        for (int c = 0; c < MATRIX_SIZE; c++)
            B[r*MATRIX_SIZE + c] = (r==c) ? 1 : 0;
    for (int i = 0; i < NUM_ELEMS; i++) C[i] = 0;

    printf("Primed A(256B), B(256B), C(1024B)\n");

    // Program A/B/C base addresses (LSB/MSB)
    REG32(REG_A_LSB) = (uint32_t)(A_PHYS & 0xFFFFFFFFu);
    REG32(REG_A_MSB) = (uint32_t)(A_PHYS >> 32);
    REG32(REG_B_LSB) = (uint32_t)(B_PHYS & 0xFFFFFFFFu);
    REG32(REG_B_MSB) = (uint32_t)(B_PHYS >> 32);
    REG32(REG_C_LSB) = (uint32_t)(C_PHYS & 0xFFFFFFFFu);
    REG32(REG_C_MSB) = (uint32_t)(C_PHYS >> 32);

    // Read-back (nice sanity check)
    uint64_t rbA = ((uint64_t)REG32(REG_A_MSB) << 32) | REG32(REG_A_LSB);
    uint64_t rbB = ((uint64_t)REG32(REG_B_MSB) << 32) | REG32(REG_B_LSB);
    uint64_t rbC = ((uint64_t)REG32(REG_C_MSB) << 32) | REG32(REG_C_LSB);
    printf("Write regs: A=0x%08lx B=0x%08lx C=0x%08lx\n",
           (unsigned long)A_PHYS, (unsigned long)B_PHYS, (unsigned long)C_PHYS);
    printf("Read  regs: A=0x%08lx B=0x%08lx C=0x%08lx\n",
           (unsigned long)rbA, (unsigned long)rbB, (unsigned long)rbC);

    // START
    REG32(REG_CTRL) = 1u; // robust RTL will accept byte/word writes; this is a 32‑bit write

    // Poll STATUS: bit0=done, bit1=busy
    const uint64_t t0 = (uint64_t)clock();
    const int TIMEOUT_MS = 2000;
    int done = 0;
    for (;;) {
        uint32_t st = REG32(REG_STATUS);
        int busy = (st >> 1) & 1;
        done = st & 1;
        if (done && !busy) break;

        // timeout
        uint64_t dt_ms = (uint64_t)( (clock() - t0) * 1000.0 / CLOCKS_PER_SEC );
        if (dt_ms > (uint64_t)TIMEOUT_MS) {
            fprintf(stderr, "Timeout: STATUS=0x%08x (done=%d busy=%d)\n", st, done, busy);
            break;
        }
    }

    if (!done) {
        fprintf(stderr, "Accelerator did not signal DONE\n");
        munmap((void*)((uintptr_t)regs & ~((size_t)sysconf(_SC_PAGESIZE)-1)), ACC_MAP_SIZE);
        munmap((void*)((uintptr_t)ddr  & ~((size_t)sysconf(_SC_PAGESIZE)-1)), DDR_MAP_SIZE);
        close(fd);
        return 2;
    }
    printf("DONE\n");

    // Verify: since B=I, we expect C == A (but widened to int32)
    int mism = 0;
    for (int i = 0; i < NUM_ELEMS; i++) {
        int32_t got = C[i];
        int32_t exp = (int32_t)A[i];
        if (got != exp) {
            if (mism < 10) {
                int r = i / MATRIX_SIZE, c = i % MATRIX_SIZE;
                printf("mismatch @(%d,%d) idx %d: exp %d got %d\n", r, c, i, exp, got);
            }
            mism++;
        }
    }
    if (mism == 0) {
        printf("PASS: C == A\n");
    } else {
        printf("FAIL: %d mismatches\n", mism);
    }

    // Peek a few outputs
    printf("C[0..3]= ");
    for (int i = 0; i < 4; i++) printf("0x%08x ", (uint32_t)C[i]);
    printf("\n");

    // Cleanup
    // (let the OS unmap on exit; explicit munmap is fine if you prefer)
    close(fd);
    return (mism==0) ? 0 : 1;
}
