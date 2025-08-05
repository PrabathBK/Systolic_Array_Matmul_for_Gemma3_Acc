#include "uart.h"
#include "stdlib.h"

// required by the crt.S startup code
typedef unsigned long UL;
UL g_program_entry;
volatile UL core_flag;
UL g_dtb_address;

// Accelerator register offsets
#define ACC_BASE        0x20060000
#define ACC_CONTROL     (ACC_BASE + 0x00)
#define ACC_STATUS      (ACC_BASE + 0x04)
#define ACC_ADDR_A_LSB  (ACC_BASE + 0x10)
#define ACC_ADDR_A_MSB  (ACC_BASE + 0x14)
#define ACC_ADDR_B_LSB  (ACC_BASE + 0x18)
#define ACC_ADDR_B_MSB  (ACC_BASE + 0x1C)
#define ACC_ADDR_C_LSB  (ACC_BASE + 0x20)
#define ACC_ADDR_C_MSB  (ACC_BASE + 0x24)

// Matrix geometry
#define MATRIX_SIZE     16
#define NUM_ELEMENTS    (MATRIX_SIZE * MATRIX_SIZE)
#define MATRIX_A_ADDR   0x20000
#define MATRIX_B_ADDR   0x21000
#define MATRIX_C_ADDR   0x22000

// Simple MMIO write
static inline void write_reg(unsigned int addr, unsigned int val) {
    *(volatile unsigned int*)addr = val;
}

int main(void) {
    // 1) UART bring-up
    init_uart(0x1B);
    printf("S> Gemma3 INT8 Accelerator Test: A * I = A\n");

    // 2) Disable CPU caching on 0x20000–(0x22000+NUM*4)
    volatile UL *fb_start = (volatile UL*)0x10301030;
    volatile UL *fb_end   = (volatile UL*)0x10301038;
    *fb_start = MATRIX_A_ADDR;
    *fb_end   = MATRIX_C_ADDR + NUM_ELEMENTS * sizeof(int);

    // 3) Prepare input matrices in uncached SRAM
    volatile signed char *mat_a = (volatile signed char*)MATRIX_A_ADDR;
    volatile signed char *mat_b = (volatile signed char*)MATRIX_B_ADDR;
    // A = [1,2,3…]
    for (int i = 0; i < NUM_ELEMENTS; i++) {
        mat_a[i] = (signed char)(i + 1);
    }
    // B = identity
    for (int r = 0; r < MATRIX_SIZE; r++) {
        for (int c = 0; c < MATRIX_SIZE; c++) {
            mat_b[r*MATRIX_SIZE + c] = (r == c) ? 1 : 0;
        }
    }
    // Zero C (INT32)
    volatile signed int *res = (volatile signed int*)MATRIX_C_ADDR;
    for (int i = 0; i < NUM_ELEMENTS; i++) {
        res[i] = 0;
    }

    // 4) Program the accelerator’s base‐address registers
    write_reg(ACC_ADDR_A_LSB, MATRIX_A_ADDR);
    write_reg(ACC_ADDR_A_MSB, 0x0);
    write_reg(ACC_ADDR_B_LSB, MATRIX_B_ADDR);
    write_reg(ACC_ADDR_B_MSB, 0x0);
    write_reg(ACC_ADDR_C_LSB, MATRIX_C_ADDR);
    write_reg(ACC_ADDR_C_MSB, 0x0);

    // 5) Kick off the operation
    printf("[i] starting accelerator...\n");
    write_reg(ACC_CONTROL, 0x1);

    // 6) Poll DONE = bit 1 of STATUS (0x04)
    volatile unsigned int *status = (volatile unsigned int*)ACC_STATUS;
    while ((*status & 0x2) != 0x2)
        ;  // wait

    printf("[✓] accelerator finished\n");

    // 7) Verify results (since B was identity, C == A)
    printf("[i] verifying results...\n");
    int mismatches = 0;
    for (int i = 0; i < NUM_ELEMENTS; i++) {
        signed int got = res[i];
        signed int exp = (signed int)mat_a[i];
        if (got != exp) {
            mismatches++;
            if (mismatches < 5) {
                printf("[✕] idx %d: expected %d, got %d\n", i, exp, got);
            }
        }
    }
    if (mismatches == 0) {
        printf("[✓] test PASSED!\n");
    } else {
        printf("[✕] FAILED with %d mismatches.\n", mismatches);
    }

    printf("E>\n");
    while (1) { /* spin */ }
}
