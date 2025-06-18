## Gemma3 Acceleration IP Design 
 
### Systolic Array Matrix Multiplier (AXI4-Lite + AXI4-Stream)

This implements a parameterizable **systolic array matrix multiplier** with:

✅ **AXI4-Lite** control interface  
✅ **AXI4-Stream** data loading interface  
✅ **INT4 configurable data width**  
✅ **Self-checking SystemVerilog testbench**  
✅ **Supports multiple test patterns**

---
### Features

- Modular processing elements (`pe.v`)
- Flexible array size (`SIZE` param)
- Configurable buffer depth (`BUFFER_DEPTH`)
- AXI4-Lite for configuration + status
- AXI4-Stream for feeding matrices
- Built-in self-checking testbench with:
  - Zero matrix test
  - Identity matrix test
  - Max value matrix test
  - Checkerboard test
  - Sparse diagonal test
  - Incrementing pattern
  - Random pattern
  - Custom A/B matrix test
- Automatic result comparison and report

---

### Key Parameters

| Parameter    | Description                         | Default |
|--------------|-------------------------------------|---------|
| `SIZE`       | Matrix dimension (NxN)              | 8       |
| `DATA_WIDTH` | Bit width per element (INT4 used)   | 4       |
| `BUFFER_DEPTH` | Internal buffer depth             | 256     |

---

### How to Simulate
Clone this repository and navigate to the Scalable_sytolic_matmul_axi folder.Make sure to compile all RTL modules (pe.v, systolic_array_with_buffers.v, systolic_array_axi_stream.v) first.Use your simulator (Vivado xsim, Questa, VCS, etc.) to compile tb_systolic_array_axi_stream.sv and run the simulation.

