#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	for(int i = 0; i < N; i++) {
		inputbuffer[i] = 0;
		outputsignal[i] = 0;
	}
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	for(int i = 0; i < N; i++) {
		int fir_result = 0;
		inputbuffer[i] = inputsignal[i];
		for(int j = 0; j <= i ; j++) {
			fir_result += inputbuffer[j] * taps[i-j];
		}
		outputsignal[i] = fir_result;
	
	}
	return outputsignal;
}
		
