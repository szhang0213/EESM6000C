**EESM600C Lab3 Skeleton**
===
**Skeleton Overview**
---
* report                
* sim                
         * fir_tb.v: The testbench for FIR. There is a random delay between sending awaddr and wdata.              
* src                
        * fir.v                        
1. fir_tb.v: In this testbench, awaddr is sent first, waiting for a random delay before sending wdata.
