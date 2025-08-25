# Systolic Array Matrix Multiplication IPs for Gemma LLM Accelerator

This repository contains multiple **systolic array accelerator IPs** designed to accelerate the **Gemma LLM inference engine** on FPGA/SoC platforms. It includes parameterized RTL implementations, tiling extensions, host test software, and integration with the **VEGA RISC-V processor**.

## 🚀 Features

- **High-throughput INT8 systolic array** accelerators (16×16, 32×32)
- **Tiling support**: large matrix multiplication using smaller arrays (e.g., 32×32 via 16×16 tiles)
- **Scalable systolic arrays**: INT4/FP16 variants, parametrized dimensions
- **AXI-Lite + AXI4 interfaces** for CPU-controlled SoC integration
- **Full Vivado testbenches** for simulation and verification
- **Integration with VEGA SoC** for real benchmarks
- Includes **waveform captures, benchmark results, and block diagrams** for documentation

## 📂 Repository Structure

```
Systolic_Array_Matmul_for_Gemma3_Acc/
├── Accelerator_IP/
│   ├── Gemma_Accelerator_IP/
│   │   ├── INT8_16x16/                    # 16x16 INT8 systolic array IP
│   │   ├── INT8_32x32/                    # 32x32 INT8 systolic array IP
│   │   └── Tiling/                        # Tiling implementation (32x32 using 16x16)
│   └── Systolic_array_IP/
│       ├── Scalable_sytolic_matmul_axi/
│       │   ├── INT4_INT4/
│       │   │   ├── Final_DMA_v2/          # DMA-enabled version
│       │   │   └── Final_v1/              # Basic version
│       │   └── f16_INT4/                  # FP16×INT4 implementation
│       ├── not_scalable_systolic_matmul/  # Initial fixed-size design
│       └── scalable_systolic_matmul/      # Parameterized systolic arrays
├── Application/
│   └── INT8_16x16/
│       ├── benchmark.c                    # Performance benchmarking code
│       ├── host.c                         # Host-side control software
│       ├── main.c                         # Main application entry point
│       └── matmul_offload.c              # Matrix multiplication offload functions
├── .gitattributes
└── README.md
```

## 🖼️ Architecture Overview

### Systolic Array Block Diagram
![systolic array architecture diagram](https://github.com/PrabathBK/Systolic_Array_Matmul_for_Gemma3_Acc/blob/main/Results/sys_block.png)


The systolic array consists of a grid of Processing Elements (PEs) that perform matrix multiplication in a pipelined fashion. Data flows through the array in a wave-like pattern, maximizing computational throughput.

### Tiling Architecture (32×32 via 16×16 tiles)
![Tilling architecture diagram](https://github.com/PrabathBK/Systolic_Array_Matmul_for_Gemma3_Acc/blob/main/Results/Acc_IP.png)

The tiling implementation allows larger matrix multiplications by decomposing them into smaller sub-matrices that fit within the 16×16 systolic array, then combining the results.

## 🧩 Key RTL Modules

### Gemma Accelerator IP
- **`gemma_accelerator.v`** - Top-level module with AXI-Lite control registers and AXI4 memory interfaces
- **`systolic_array_16x16.v`** - Configurable 16×16 systolic array grid
- **`pe_int8.v`** - Processing element: INT8×INT8 multiply with 32-bit accumulation
- **`accelerator_buffer.v`** - Input/output buffers for A, B matrices and result staging

### Systolic Array IP Variants
- **Scalable Implementation**: Parameterized systolic arrays supporting various dimensions
- **INT4 Support**: Optimized for quantized neural network inference
- **FP16×INT4**: Mixed-precision multiplication for enhanced accuracy
- **DMA Integration**: Direct memory access for improved data transfer efficiency

## 📊 Benchmarks & Results

### Simulation and Implementation Results

#### INT8 16×16 IP on VEGA Processor SoC
- ✅ **Simulation verified** (waveform screenshots below)
![IP Wave - Data flow](https://github.com/PrabathBK/Systolic_Array_Matmul_for_Gemma3_Acc/blob/main/Results/IP1.png)
![IP Wave - Results](https://github.com/PrabathBK/Systolic_Array_Matmul_for_Gemma3_Acc/blob/main/Results/IP2.png)

- ✅ **Hardware implementation successful - Benchmark**
![Systolic SOC Benchmark](https://github.com/PrabathBK/Systolic_Array_Matmul_for_Gemma3_Acc/blob/main/Results/systolic_soc_implementation.png)

- ✅ **Hardware implementation successful - Offload**
![Systolic SOC offload](https://github.com/PrabathBK/Systolic_Array_Matmul_for_Gemma3_Acc/blob/main/Results/offload_result.jpeg)


#### Tiling IP (32×32 using 16×16 systolic array) on SoC
- ✅ **Implementation Results**
![Systolic SOC Benchmark](https://github.com/PrabathBK/Systolic_Array_Matmul_for_Gemma3_Acc/blob/main/Results/Tiling_log.png)



#### Integration with VEGA Processor

1. **Load data into memory** (A, B matrices)
2. **Configure accelerator via AXI-Lite**:
   - Write base addresses (A, B, C matrices)
   - Set matrix dimensions
   - Set start bit
3. **Wait for completion** (done flag or interrupt)
4. **Read results from memory** (C matrix)


## 🔧 Configuration Options

### Compile-time Parameters
- `ARRAY_SIZE`: Systolic array dimensions (default: 16)
- `DATA_WIDTH`: Input data width (8 for INT8, 4 for INT4)
- `ACCUMULATOR_WIDTH`: Output accumulator width (default: 32)
- `BUFFER_DEPTH`: Input/output buffer depth

### Runtime Configuration
- Matrix dimensions (up to maximum supported by array size)
- Memory addresses for input/output matrices
- Interrupt enable/disable
- Debug mode enable/disable

## 🚀 Performance Optimization Tips

1. **Memory Layout**: Use contiguous memory allocation for better cache performance
2. **Data Alignment**: Align matrices to cache line boundaries
3. **Tiling Strategy**: Choose tile sizes that maximize array utilization
4. **Pipeline Optimization**: Overlap data loading with computation when possible


**Note**: This accelerator is designed specifically for the Gemma LLM inference pipeline and may require modifications for other neural network architectures.
