
#include <stdint.h>

#include "unit_test.h"

#define DECL_RD_CSR(CSR) volatile inline uint64_t rd_##CSR() { \
    uint64_t rd; asm volatile ("csrr %0, " #CSR : "=r"(rd)); return rd; \
}

#define DECL_WR_CSR(CSR) volatile inline void wr_##CSR(uint64_t rs1) { \
    asm volatile ("csrw " #CSR ", %0" : : "r"(rs1));   \
}

DECL_RD_CSR(mcause)
DECL_RD_CSR(mtvec)
DECL_WR_CSR(mtvec)

// Flag set/cleared by c_trap_handler.
int test_passed = 0;

extern void test_trap_handler();

void c_trap_handler()  {

    int64_t mcause = (int64_t)rd_mcause();

    if(mcause < 0) {
        // This test should not deal with any interrupts.
        test_fail();
    }

    __putstr("mcause: "); __puthex8(mcause); __putchar('\n');

    if(mcause == CAUSE_CODE_IACCESS) {
        test_passed += 1;
    } else {
        test_fail();
    }
    
    return;
}

int test_main() {

    // Set MTVEC to the trap handler.
    wr_mtvec((uint64_t)(&test_trap_handler));

    // Jump to a non-existant physical address. -1 in this case.
    int tgt_addr = -1;
    asm ("jr %0" : : "r"(tgt_addr));

    // Check we saw the exception handler only once.
    if(test_passed == 1) {
        test_pass();
    } else {
        test_fail();
    }

    return 0;

}
