#ifndef __FIR_H__
#define __FIR_H__

#define N 11

#define reg_fir_control  (*(volatile uint32_t*)0x30000000)
#define reg_fir_coeff(i) (*(volatile uint32_t*)(0x30000080 + (i << 2)))
#define reg_fir_x	 (*(volatile uint32_t*)0x30000040)
#define reg_fir_y	 (*(volatile uint32_t*)0x30000044)

int taps[N] = {0,-10,-9,23,56,63,56,23,-9,-10,0};
int inputbuffer[N];
int inputsignal[N] = {1,2,3,4,5,6,7,8,9,10,11};
int outputsignal[N];
#endif
