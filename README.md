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
![systolic array architecture diagram](/Users/prabathwijethilaka/DVCON/Systolic_Array_Matmul_for_Gemma3_Acc/Systolic_Array_Matmul_for_Gemma3_Acc/sys_block.png)


The systolic array consists of a grid of Processing Elements (PEs) that perform matrix multiplication in a pipelined fashion. Data flows through the array in a wave-like pattern, maximizing computational throughput.

### Tiling Architecture (32×32 via 16×16 tiles)
*[Placeholder: Insert tiling diagram image]*

The tiling implementation allows larger matrix multiplications by decomposing them into smaller sub-matrices that fit within the 16×16 systolic array, then combining the results.

## 🧩 Key RTL Modules

### Gemma Accelerator IP
- **`gemma_accelerator.v`** - Top-level module with AXI-Lite control registers and AXI4 memory interfaces
- **`systolic_array_16x16.v`** - Configurable 16×16 systolic array grid
- **`pe_int8.v`** - Processing element: INT8×INT8 multiply with 32-bit accumulation
- **`accelerator_buffer.v`** - Input/output buffers for A, B matrices and result staging
- **`axi_control_fsm.v`** - Finite state machine for AXI transaction control

### Systolic Array IP Variants
- **Scalable Implementation**: Parameterized systolic arrays supporting various dimensions
- **INT4 Support**: Optimized for quantized neural network inference
- **FP16×INT4**: Mixed-precision multiplication for enhanced accuracy
- **DMA Integration**: Direct memory access for improved data transfer efficiency

## 📊 Benchmarks & Results

### Simulation and Implementation Results

#### INT8 16×16 IP on VEGA Processor SoC
- ✅ **Simulation verified** (waveform screenshots below)
- ✅ **Hardware implementation successful** 
- ✅ **Benchmarks executed** (performance results below)

*[Placeholder: Insert waveform screenshot 1]*
*[Placeholder: Insert waveform screenshot 2]*
*[Placeholder: Insert benchmark performance image]*

#### Tiling IP (32×32 using 16×16 array) on SoC
- ✅ **Implementation passed**
- ✅ **Benchmark completed successfully**

*[Placeholder: Insert tiling implementation results image]*

### Performance Metrics
- **Throughput**: X GOPS (Giga Operations Per Second)
- **Latency**: Y cycles for 16×16 matrix multiplication
- **Resource Utilization**: 
  - LUTs: X%
  - DSPs: Y%
  - BRAM: Z%
- **Power Consumption**: W watts at X MHz

## 🛠️ How to Use

### Prerequisites
- Xilinx Vivado 2021.1 or later
- VEGA RISC-V processor development environment
- GCC cross-compiler for RISC-V

### Building the RTL Design

1. **Clone the repository**:
   ```bash
   git clone https://github.com/PrabathBK/Systolic_Array_Matmul_for_Gemma3_Acc.git
   cd Systolic_Array_Matmul_for_Gemma3_Acc
   ```

2. **Open in Vivado**:
   ```bash
   cd Accelerator_IP/Gemma_Accelerator_IP/INT8_16x16/
   vivado -source build_project.tcl
   ```

3. **Run synthesis and implementation**:
   ```tcl
   launch_runs synth_1
   wait_on_run synth_1
   launch_runs impl_1 -to_step write_bitstream
   wait_on_run impl_1
   ```

### Software Integration

#### Compiling the Host Application
```bash
cd Application/INT8_16x16/
riscv64-unknown-elf-gcc -O2 -o matmul_test main.c host.c matmul_offload.c benchmark.c
```

#### Integration with VEGA Processor

1. **Load data into memory** (A, B matrices)
2. **Configure accelerator via AXI-Lite**:
   - Write base addresses (A, B, C matrices)
   - Set matrix dimensions
   - Set start bit
3. **Wait for completion** (done flag or interrupt)
4. **Read results from memory** (C matrix)

#### Example Usage
```c
// Initialize accelerator
accelerator_init(ACCELERATOR_BASE_ADDR);

// Set up matrices
set_matrix_a_addr(matrix_a_addr);
set_matrix_b_addr(matrix_b_addr);
set_result_addr(result_addr);
set_dimensions(16, 16, 16);

// Start computation
start_accelerator();

// Wait for completion
while(!is_accelerator_done()) {
    // Poll or wait for interrupt
}

// Results are now available in result_addr
```

### Running Testbenches

#### Simulation
```bash
cd Accelerator_IP/Gemma_Accelerator_IP/INT8_16x16/testbench/
vivado -mode batch -source run_simulation.tcl
```

#### Benchmark Testing
```bash
cd Application/INT8_16x16/
./matmul_test
```

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

## 📈 Roadmap

- [ ] **Larger array implementations** (64×64, 128×128)
- [ ] **Advanced scheduling**: overlapping DMA + compute operations
- [ ] **Post-processing ops**: ReLU, quantization, normalization
- [ ] **Support for more LLM layers**: attention mechanisms, projection layers
- [ ] **Multi-precision support**: FP16, BF16, INT16
- [ ] **Power optimization**: clock gating, voltage scaling
- [ ] **Software stack**: PyTorch/TensorFlow integration

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- VEGA RISC-V processor development team
- Gemma LLM research community
- Xilinx/AMD for development tools and documentation

## 📧 Contact

For questions or collaboration opportunities, please open an issue or contact the repository maintainer.

---

**Note**: This accelerator is designed specifically for the Gemma LLM inference pipeline and may require modifications for other neural network architectures.