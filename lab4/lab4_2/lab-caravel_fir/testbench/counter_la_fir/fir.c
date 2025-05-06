#include "fir.h"
#include <stdint.h>
#include <defs.h>

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	for(uint32_t i = 0; i < N; i++){
		reg_fir_coeff(i) = taps[i];
	}
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	reg_fir_control = 0x00000001;
	
	reg_mprj_datal = 0x00A50000; // start Testbench
	
	for (int i = 1; i <= N; i++) {
		reg_fir_x = i;
		outputsignal[i] = reg_fir_y;
	}
	
	reg_mprj_datal = (outputsignal[N] << 24) + 0x005A0000; // end Testbench
	
	return outputsignal;
}
		
