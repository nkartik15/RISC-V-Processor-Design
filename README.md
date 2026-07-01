# ⚡ RISC-V Processor Design

> A RISC-V CPU built from the ground up in Verilog — no shortcuts, not even on the adder.

This repo houses **two complete RV32I CPUs**, built with the same core components:

| | Single-Cycle | 5-Stage Pipeline |
|---|---|---|
| File | `cputop.v` | `cpu_pipeline.v` |
| Vibe | One instruction, one clock, done. | Fetch, decode, execute, memory, writeback — all happening at once, five instructions deep. |
| Extras | Clean reference design | Full forwarding, hazard detection, branch flushing + hooks for power/security/macro-engine extensions |

Same building blocks under the hood, two very different ways of running them.

---

## 🗂️ What's Inside

```
RTL/
  PC.v                    – Program counter
  Instructionmemory.v     – Instruction memory (hex-loaded ROM)
  register.v              – 32×32 register file
  immediate_generator.v   – Immediate decoder (I/S/B/U/J formats)
  controlunit.v           – Main control + ALU control
  alu.v                   – ALU, powered by a hand-built Carry-Select Adder
  data_mem.v              – Byte-addressable data memory
  hazard_unit.v           – Forwarding + stall detection
  cputop.v                – Single-cycle CPU
  cpu_pipeline.v          – 5-stage pipelined CPU
TestBench/
  test_bench_*.v          – One testbench per module, plus full-system tests
```

---

## 🔧 The Building Blocks

**`PC.v`** — The program counter. Decides what's next with a clean priority ladder: JALR beats JAL/branch beats plain old `pc+4`.

**`Instructionmemory.v`** — A 256-word ROM loaded straight from a hex file. Ask for something out of range and it politely hands you a NOP instead of crashing.

**`register.v`** — The classic 32×32 register file, with `x0` permanently wired to zero (as the ISA gods intended).

**`immediate_generator.v`** — Untangles RISC-V's five different immediate encodings (I/S/B/U/J) into one clean sign-extended output.

**`controlunit.v`** — The decision-maker. `maincontrol` reads the opcode and flips every switch in the datapath; `alucontrol` figures out exactly which ALU op to run.

**`alu.v`** — The star of the show. Instead of leaning on `+`, the adder is a **custom 32-bit Carry-Select Adder with Binary-to-Excess-1 speedup**, built from four 8-bit ripple-carry blocks. Handles all of RV32I's arithmetic, logic, shifts, and comparisons.

**`data_mem.v`** — 1 KB of byte-addressable memory that speaks fluent LB/LH/LW/LBU/LHU/SB/SH/SW.

**`hazard_unit.v`** — The pipeline's safety net: catches load-use hazards (inserts a stall) and routes forwarding paths so the EX stage always sees fresh data.

**`cputop.v`** — Everything above, wired into a single-cycle CPU. One instruction per clock, full branch support (BEQ/BNE/BLT/BGE/BLTU/BGEU), plus LUI/AUIPC handled cleanly via an operand-A mux.

**`cpu_pipeline.v`** — The main event: a proper 5-stage pipeline.
- **IF** → fetch, with redirect/stall/macro-injection priority baked into the PC logic
- **ID** → decode + register read, with a **WB→ID bypass** to dodge the read-before-write race in the register file
- **EX** → ALU + forwarding muxes + branch resolution (this is where control-flow changes get decided — costs a 2-instruction flush when a branch is taken)
- **MEM** → data memory access
- **WB** → writeback mux (link address, load data, or ALU result)

It also comes pre-wired with **extension ports that aren't used yet** — sideband buses for a future power-control module, a security-tagging module, and a macro-instruction engine. Nothing's implemented there yet, but the plumbing's ready.

---

## 🧪 Testbenches

Every module gets its own testbench (PC, register file, ALU, control unit, data memory, hazard unit, immediate generator...), plus dedicated tests for full pipeline behavior, branch/jump handling, and pipeline hazard stress-testing.

---

## 💡 Little Details Worth Knowing

- The adder isn't lazy — it's a real carry-select design, probably built as a VLSI/arch-course exercise in speeding up addition.
- The pipeline was clearly designed with room to grow: power, security, and macro-engine hooks are threaded through every pipeline register even though nothing plugs into them yet.
- Memories are simulation-style (`reg` arrays + `$readmemh`) — great for testing, would need to be swapped for real memory macros on silicon/FPGA.
