#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	for(int i = 0; i < N; i++){
		reg_fir_coeff(i) = taps[i];
	}
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	reg_fir_control = 0x00000001;
	for(int i = 0; i < N; i++){
		reg_fir_x = i;
		
	}
	return outputsignal;
}
		
