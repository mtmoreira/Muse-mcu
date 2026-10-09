// ----------------------------------------------------------------------------
// rv32i_cpu.sv -- Muse MCU RV32I + Zicsr CPU core (machine mode only)
//
// Fresh implementation for the Muse-mcu project. No code is reused from any
// prior core; only design knowledge is carried over.
//
// Microarchitecture: single-cycle, single-issue, in-order. The instruction
// bus (if_rdata/if_fault) and the data bus (d_rdata/d_fault) are
// combinational, so every instruction -- including loads, stores and CSR
// accesses -- retires in exactly one cycle. CPI = 1.
//
// Trap model: direct mtvec only (no vectored mode, no nesting). Synchronous
// traps (fetch access fault, illegal instruction, ecall, ebreak, misaligned
// load/store address, load/store access fault) take precedence over pending
// interrupts. Interrupts are evaluated at instruction boundaries: when one is
// taken the current instruction is NOT retired -- it is deferred and
// re-fetched after the handler returns via MRET (mepc holds its PC).
//
// Bus interface notes:
//  * d_wstrb == 0 denotes a read. The CPU drives d_addr every cycle; when the
//    current instruction performs no data access, d_addr is forced to 0
//    (BOOTROM base, always mapped) so the bus never faults spuriously.
//  * d_wstrb is suppressed (forced to 0) on any trap-taken cycle so a
//    deferred or faulting store is never issued to the bus. This is
//    combinationally safe because d_fault is a pure function of d_addr
//    ("unmapped access" per the interface contract); d_addr itself is never
//    gated on the trap decision, so no combinational loop is formed.
//  * A load whose address is presented on an interrupt-taken cycle still
//    performs its bus read (the interface has no read-valid signal to
//    suppress it); the value is discarded and the load re-executes after
//    MRET. MMIO with destructive read side effects should be accessed with
//    interrupts disabled if a deferred extra read is unacceptable.
//
// Reset: synchronous, active high, minimum 1 cycle. pc <= 0x00000000,
// register file and all CSRs <= 0. Every flop has a defined reset value;
// no reliance on X.
// ----------------------------------------------------------------------------

module rv32i_cpu (
  input  logic        clk,
  input  logic        rst,              // synchronous, active high
  output logic [31:0] if_addr,          // instruction fetch address
  input  logic [31:0] if_rdata,         // combinational
  input  logic        if_fault,         // combinational, unmapped fetch
  output logic [31:0] d_addr,           // data address
  output logic [31:0] d_wdata,
  output logic [3:0]  d_wstrb,          // byte strobes; 0 = read
  input  logic [31:0] d_rdata,          // combinational
  input  logic        d_fault,          // combinational, unmapped access
  input  logic        irq_timer,        // MTI
  input  logic        irq_sw,           // MSI
  input  logic        irq_ext,          // MEI
  output logic [31:0] dbg_pc,
  output logic        dbg_instr_valid,  // 1 when an instruction retires this cycle
  output logic        dbg_trap_taken,   // 1 when a trap is taken this cycle
  output logic [31:0] dbg_mcause
);

  // ------------------------------------------------------------------
  // Architectural state
  // ------------------------------------------------------------------
  logic [31:0] pc_q;
  logic [31:0] rf [0:31];          // integer register file; x0 reads as 0

  logic        mie_q;              // mstatus.MIE  (bit 3)
  logic        mpie_q;             // mstatus.MPIE (bit 7)
  logic        msie_q;             // mie.MSIE (bit 3)
  logic        mtie_q;             // mie.MTIE (bit 7)
  logic        meie_q;             // mie.MEIE (bit 11)
  logic [29:0] mtvec_base_q;       // mtvec[31:2]; mtvec[1:0] hardwired 0
  logic [31:0] mscratch_q;
  logic [31:0] mepc_q;
  logic [31:0] mcause_q;
  logic [31:0] mtval_q;
  logic [31:0] mcycle_q;
  logic [31:0] minstret_q;

  // ------------------------------------------------------------------
  // Instruction decode
  // ------------------------------------------------------------------
  wire [31:0] instr   = if_rdata;
  wire [6:0]  opcode  = instr[6:0];
  wire [4:0]  rd      = instr[11:7];
  wire [2:0]  funct3  = instr[14:12];
  wire [4:0]  rs1     = instr[19:15];
  wire [4:0]  rs2     = instr[24:20];
  wire [6:0]  funct7  = instr[31:25];
  wire [11:0] csr_addr = instr[31:20];
  wire [4:0]  uimm    = instr[19:15];

  // Immediates
  wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
  wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
  wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25],
                        instr[11:8], 1'b0};
  wire [31:0] imm_u = {instr[31:12], 12'b0};
  wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20],
                        instr[30:21], 1'b0};

  // Opcode classes
  wire op_lui    = (opcode == 7'b0110111);
  wire op_auipc  = (opcode == 7'b0010111);
  wire op_jal    = (opcode == 7'b1101111);
  wire op_jalr   = (opcode == 7'b1100111);
  wire op_branch = (opcode == 7'b1100011);
  wire op_load   = (opcode == 7'b0000011);
  wire op_store  = (opcode == 7'b0100011);
  wire op_imm    = (opcode == 7'b0010011);
  wire op_op     = (opcode == 7'b0110011);
  wire op_fence  = (opcode == 7'b0001111);
  wire op_system = (opcode == 7'b1110011);

  // Register file read ports (x0 hardwired to zero)
  wire [31:0] rs1_data = (rs1 == 5'd0) ? 32'h0 : rf[rs1];
  wire [31:0] rs2_data = (rs2 == 5'd0) ? 32'h0 : rf[rs2];

  // ------------------------------------------------------------------
  // CSR file: read mux
  // ------------------------------------------------------------------
  logic [31:0] csr_rdata;
  always_comb begin
    case (csr_addr)
      12'h300: csr_rdata = {24'h0, mpie_q, 3'b0, mie_q, 3'b0};
      12'h301: csr_rdata = 32'h40000100;                       // misa
      12'h304: csr_rdata = {20'h0, meie_q, 3'b0, mtie_q, 3'b0, msie_q, 3'b0};
      12'h305: csr_rdata = {mtvec_base_q, 2'b00};
      12'h340: csr_rdata = mscratch_q;
      12'h341: csr_rdata = mepc_q;
      12'h342: csr_rdata = mcause_q;
      12'h343: csr_rdata = mtval_q;
      12'h344: csr_rdata = {20'h0, irq_ext, 3'b0, irq_timer, 3'b0, irq_sw, 3'b0};
      12'hB00: csr_rdata = mcycle_q;
      12'hB02: csr_rdata = minstret_q;
      default: csr_rdata = 32'h0;
    endcase
  end

  // CSR legality: undefined address -> illegal; write to read-only -> illegal.
  // CSRRS/CSRRC with rs1==x0 (uimm==0 for the immediate forms) perform no
  // write, so they never fault on a read-only CSR.
  wire csr_defined =
      (csr_addr == 12'h300) || (csr_addr == 12'h301) || (csr_addr == 12'h304) ||
      (csr_addr == 12'h305) || (csr_addr == 12'h340) || (csr_addr == 12'h341) ||
      (csr_addr == 12'h342) || (csr_addr == 12'h343) || (csr_addr == 12'h344) ||
      (csr_addr == 12'hB00) || (csr_addr == 12'hB02);
  wire csr_readonly =
      (csr_addr == 12'h301) || (csr_addr == 12'h344) ||
      (csr_addr == 12'hB00) || (csr_addr == 12'hB02);

  wire sys_is_csr = (funct3 == 3'b001) || (funct3 == 3'b010) ||
                    (funct3 == 3'b011) || (funct3 == 3'b101) ||
                    (funct3 == 3'b110) || (funct3 == 3'b111);
  wire [31:0] csr_uimm = {27'b0, uimm};

  logic [31:0] csr_wdata_pre;
  always_comb begin
    case (funct3)
      3'b001:  csr_wdata_pre = rs1_data;               // CSRRW
      3'b010:  csr_wdata_pre = csr_rdata | rs1_data;    // CSRRS
      3'b011:  csr_wdata_pre = csr_rdata & ~rs1_data;   // CSRRC
      3'b101:  csr_wdata_pre = csr_uimm;                // CSRRWI
      3'b110:  csr_wdata_pre = csr_rdata | csr_uimm;    // CSRRSI
      3'b111:  csr_wdata_pre = csr_rdata & ~csr_uimm;   // CSRRCI
      default: csr_wdata_pre = 32'h0;
    endcase
  end

  wire csr_no_write =
      ((funct3 == 3'b010) || (funct3 == 3'b011)) ? (rs1 == 5'd0) :
      ((funct3 == 3'b110) || (funct3 == 3'b111)) ? (uimm == 5'd0) : 1'b0;
  wire csr_would_write = sys_is_csr && !csr_no_write;
  wire csr_op_illegal  = !csr_defined || (csr_would_write && csr_readonly);

  // ------------------------------------------------------------------
  // SYSTEM instruction decode (privileged ops)
  // ------------------------------------------------------------------
  wire sys_funct3_000 = (funct3 == 3'b000);
  wire sys_is_ecall   = sys_funct3_000 && (csr_addr == 12'h000);
  wire sys_is_ebreak  = sys_funct3_000 && (csr_addr == 12'h001);
  wire sys_is_mret    = sys_funct3_000 && (csr_addr == 12'h302);
  // Note: WFI (0x105) is intentionally absent -> illegal instruction.
  wire sys_priv_ok    = sys_is_ecall || sys_is_ebreak || sys_is_mret;
  wire system_illegal = sys_funct3_000 ? !sys_priv_ok :
                        sys_is_csr     ? csr_op_illegal : 1'b1;

  wire dec_csr    = op_system && sys_is_csr && !csr_op_illegal;
  wire dec_ecall  = op_system && sys_is_ecall;
  wire dec_ebreak = op_system && sys_is_ebreak;
  wire dec_mret   = op_system && sys_is_mret;
  wire csr_wen    = dec_csr && csr_would_write;

  // ------------------------------------------------------------------
  // Illegal-instruction detection
  // ------------------------------------------------------------------
  wire op_imm_illegal =
      (funct3 == 3'b001) ? (funct7 != 7'b0000000) :                    // SLLI
      (funct3 == 3'b101) ? ((funct7 != 7'b0000000) &&                  // SRLI/SRAI
                            (funct7 != 7'b0100000)) :
      1'b0;
  wire op_op_illegal =
      (funct7 == 7'b0000000) ? 1'b0 :
      (funct7 == 7'b0100000) ? ((funct3 != 3'b000) && (funct3 != 3'b101)) :
      1'b1;

  wire branch_funct_ok = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                         (funct3 == 3'b100) || (funct3 == 3'b101) ||
                         (funct3 == 3'b110) || (funct3 == 3'b111);
  wire load_funct_ok   = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                         (funct3 == 3'b010) || (funct3 == 3'b100) ||
                         (funct3 == 3'b101);
  wire store_funct_ok  = (funct3 == 3'b000) || (funct3 == 3'b001) ||
                         (funct3 == 3'b010);

  wire dec_jalr   = op_jalr && (funct3 == 3'b000);
  wire dec_branch = op_branch && branch_funct_ok;
  wire dec_load   = op_load && load_funct_ok;
  wire dec_store  = op_store && store_funct_ok;

  wire illegal =
      !(op_lui || op_auipc || op_jal || op_jalr || op_branch || op_load ||
        op_store || op_imm || op_op || op_fence || op_system) ||
      (op_jalr && (funct3 != 3'b000)) ||
      (op_branch && !branch_funct_ok) ||
      (op_load && !load_funct_ok) ||
      (op_store && !store_funct_ok) ||
      (op_imm && op_imm_illegal) ||
      (op_op && op_op_illegal) ||
      (op_fence && (funct3 != 3'b000)) ||
      (op_system && system_illegal);

  // ------------------------------------------------------------------
  // ALU
  // ------------------------------------------------------------------
  wire [31:0] alu_a     = rs1_data;
  wire [31:0] alu_b     = op_op ? rs2_data : imm_i;
  wire [4:0]  alu_shamt = op_op ? rs2_data[4:0] : instr[24:20];
  wire        alu_is_sub = op_op && (funct3 == 3'b000) && (funct7 == 7'b0100000);
  wire        alu_is_sra = (funct3 == 3'b101) &&
                           (op_op ? (funct7 == 7'b0100000) : instr[30]);

  wire [31:0] alu_addsub = alu_a + (alu_is_sub ? (~alu_b + 32'd1) : alu_b);
  wire [31:0] alu_sll    = alu_a << alu_shamt;
  wire [31:0] alu_srl    = alu_a >> alu_shamt;
  // Arithmetic shift via explicit sign extension (avoids any >>> codegen
  // subtleties across simulators).
  wire [63:0] alu_sra_wide = {{32{alu_a[31]}}, alu_a} >> alu_shamt;
  wire [31:0] alu_sra    = alu_sra_wide[31:0];
  wire [31:0] alu_shr    = alu_is_sra ? alu_sra : alu_srl;
  wire        alu_lt_s   = ($signed(alu_a) < $signed(alu_b));
  wire        alu_lt_u   = (alu_a < alu_b);

  logic [31:0] alu_result;
  always_comb begin
    case (funct3)
      3'b000:  alu_result = alu_addsub;              // ADD / ADDI / SUB
      3'b001:  alu_result = alu_sll;                 // SLL / SLLI
      3'b010:  alu_result = {31'b0, alu_lt_s};       // SLT / SLTI
      3'b011:  alu_result = {31'b0, alu_lt_u};       // SLTU / SLTIU
      3'b100:  alu_result = alu_a ^ alu_b;           // XOR / XORI
      3'b101:  alu_result = alu_shr;                 // SRL / SRA
      3'b110:  alu_result = alu_a | alu_b;           // OR / ORI
      3'b111:  alu_result = alu_a & alu_b;           // AND / ANDI
      default: alu_result = 32'h0;
    endcase
  end

  // ------------------------------------------------------------------
  // Branches
  // ------------------------------------------------------------------
  logic branch_taken;
  always_comb begin
    case (funct3)
      3'b000:  branch_taken = (rs1_data == rs2_data);                 // BEQ
      3'b001:  branch_taken = (rs1_data != rs2_data);                 // BNE
      3'b100:  branch_taken = ($signed(rs1_data) < $signed(rs2_data));// BLT
      3'b101:  branch_taken = ($signed(rs1_data) >= $signed(rs2_data));// BGE
      3'b110:  branch_taken = (rs1_data < rs2_data);                  // BLTU
      3'b111:  branch_taken = (rs1_data >= rs2_data);                 // BGEU
      default: branch_taken = 1'b0;
    endcase
  end

  // ------------------------------------------------------------------
  // Load/store datapath and bus outputs
  // ------------------------------------------------------------------
  wire [31:0] mem_addr = rs1_data + (dec_store ? imm_s : imm_i);

  wire load_misaligned =
      dec_load &&
      (((funct3 == 3'b010) && (mem_addr[1:0] != 2'b00)) ||
       (((funct3 == 3'b001) || (funct3 == 3'b101)) && mem_addr[0]));
  wire store_misaligned =
      dec_store &&
      (((funct3 == 3'b010) && (mem_addr[1:0] != 2'b00)) ||
       ((funct3 == 3'b001) && mem_addr[0]));

  // Bus address is presented for decoded, aligned accesses only. It is
  // deliberately NOT gated on the trap decision: d_fault is a pure function
  // of d_addr, so gating d_addr on d_fault-derived signals would form a
  // combinational loop through the bus.
  wire bus_addr_active = (dec_load || dec_store) &&
                         !load_misaligned && !store_misaligned && !if_fault;
  assign d_addr = bus_addr_active ? mem_addr : 32'h0;

  logic [3:0]  store_strb;
  logic [31:0] store_wdata;
  always_comb begin
    case (funct3[1:0])
      2'b00: begin // SB
        store_strb  = 4'b0001 << mem_addr[1:0];
        store_wdata = {4{rs2_data[7:0]}};
      end
      2'b01: begin // SH (addr[0]==0 already guaranteed)
        store_strb  = mem_addr[1] ? 4'b1100 : 4'b0011;
        store_wdata = {2{rs2_data[15:0]}};
      end
      2'b10: begin // SW
        store_strb  = 4'b1111;
        store_wdata = rs2_data;
      end
      default: begin
        store_strb  = 4'b0000;
        store_wdata = 32'h0;
      end
    endcase
  end

  // Load data extraction from the combinational bus read data.
  wire [31:0] load_bshift = d_rdata >> (8 * {30'b0, mem_addr[1:0]});
  wire [31:0] load_hshift = d_rdata >> (16 * {31'b0, mem_addr[1]});
  logic [31:0] load_data;
  always_comb begin
    case (funct3)
      3'b000:  load_data = {{24{load_bshift[7]}}, load_bshift[7:0]};  // LB
      3'b001:  load_data = {{16{load_hshift[15]}}, load_hshift[15:0]};// LH
      3'b010:  load_data = d_rdata;                                  // LW
      3'b100:  load_data = {24'b0, load_bshift[7:0]};                // LBU
      3'b101:  load_data = {16'b0, load_hshift[15:0]};                // LHU
      default: load_data = 32'h0;
    endcase
  end

  // ------------------------------------------------------------------
  // Trap computation
  //
  // Synchronous trap priority: fetch access fault > illegal instruction >
  // misaligned load/store > load/store access fault > ecall > ebreak.
  // A synchronous trap takes precedence over a pending interrupt.
  // ------------------------------------------------------------------
  wire load_fault  = dec_load && !load_misaligned && d_fault;
  wire store_fault = dec_store && !store_misaligned && d_fault;

  wire sync_trap = if_fault || illegal ||
                   (dec_load && load_misaligned) ||
                   (dec_store && store_misaligned) ||
                   load_fault || store_fault ||
                   dec_ecall || dec_ebreak;

  // Interrupt pending: MIE && (mie & mip) != 0. Priority MEI > MSI > MTI.
  wire irq_mei_pending = meie_q && irq_ext;
  wire irq_msi_pending = msie_q && irq_sw;
  wire irq_mti_pending = mtie_q && irq_timer;
  wire irq_pending = mie_q &&
      (irq_mei_pending || irq_msi_pending || irq_mti_pending);
  wire irq_trap = !sync_trap && irq_pending;

  wire [31:0] irq_cause = irq_mei_pending ? 32'h8000000B :
                          irq_msi_pending ? 32'h80000003 :
                          32'h80000007;

  logic [31:0] trap_cause;
  always_comb begin
    if (if_fault)                        trap_cause = 32'd1;
    else if (illegal)                    trap_cause = 32'd2;
    else if (dec_load && load_misaligned) trap_cause = 32'd4;
    else if (dec_store && store_misaligned) trap_cause = 32'd6;
    else if (load_fault)                 trap_cause = 32'd5;
    else if (store_fault)                trap_cause = 32'd7;
    else if (dec_ecall)                  trap_cause = 32'd11;
    else if (dec_ebreak)                 trap_cause = 32'd3;
    else                                 trap_cause = irq_cause;
  end

  logic [31:0] trap_mtval;
  always_comb begin
    if (if_fault)      trap_mtval = if_addr;
    else if (illegal)  trap_mtval = instr;
    else if ((dec_load && load_misaligned) || (dec_store && store_misaligned) ||
             load_fault || store_fault)
                       trap_mtval = mem_addr;
    else               trap_mtval = 32'h0;   // ecall, ebreak, interrupts
  end

  wire trap_taken = !rst && (sync_trap || irq_trap);
  wire retired    = !rst && !sync_trap && !irq_trap;

  // Write strobes are suppressed on any trap-taken cycle so a faulting or
  // interrupt-deferred store is never issued to the bus. Safe: d_fault is a
  // pure function of d_addr (unmapped-access detection), and d_addr is not
  // gated on the trap decision, so no combinational loop is formed.
  assign d_wstrb = (bus_addr_active && dec_store && !trap_taken) ?
                   store_strb : 4'b0;
  assign d_wdata = (d_wstrb != 4'b0) ? store_wdata : 32'h0;
  assign if_addr = pc_q;

  // ------------------------------------------------------------------
  // Next PC and rd write-back (applied only when the instruction retires)
  // ------------------------------------------------------------------
  wire [31:0] jalr_target = (rs1_data + imm_i) & 32'hFFFFFFFE;

  logic [31:0] pc_next;
  always_comb begin
    pc_next = pc_q + 32'd4;
    if (op_jal)                       pc_next = pc_q + imm_j;
    else if (dec_jalr)                pc_next = jalr_target;
    else if (dec_branch && branch_taken) pc_next = pc_q + imm_b;
  end

  logic        rd_wen;
  logic [31:0] rd_wdata;
  always_comb begin
    rd_wen   = 1'b0;
    rd_wdata = 32'h0;
    if (op_lui) begin
      rd_wen = 1'b1; rd_wdata = imm_u;
    end else if (op_auipc) begin
      rd_wen = 1'b1; rd_wdata = pc_q + imm_u;
    end else if (op_jal) begin
      rd_wen = 1'b1; rd_wdata = pc_q + 32'd4;
    end else if (dec_jalr) begin
      rd_wen = 1'b1; rd_wdata = pc_q + 32'd4;
    end else if (op_imm) begin
      rd_wen = 1'b1; rd_wdata = alu_result;
    end else if (op_op) begin
      rd_wen = 1'b1; rd_wdata = alu_result;
    end else if (dec_load) begin
      rd_wen = 1'b1; rd_wdata = load_data;
    end else if (dec_csr) begin
      rd_wen = 1'b1; rd_wdata = csr_rdata;
    end
    // branches, stores, FENCE, ECALL, EBREAK, MRET: no rd write
  end

  // ------------------------------------------------------------------
  // Sequential: PC, CSRs, counters
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      pc_q         <= 32'h00000000;
      mie_q        <= 1'b0;
      mpie_q       <= 1'b0;
      msie_q       <= 1'b0;
      mtie_q       <= 1'b0;
      meie_q       <= 1'b0;
      mtvec_base_q <= 30'h0;
      mscratch_q   <= 32'h0;
      mepc_q       <= 32'h0;
      mcause_q     <= 32'h0;
      mtval_q      <= 32'h0;
      mcycle_q     <= 32'h0;
      minstret_q   <= 32'h0;
    end else begin
      mcycle_q <= mcycle_q + 32'd1;
      if (trap_taken) begin
        mepc_q   <= pc_q;
        mcause_q <= trap_cause;
        mtval_q  <= trap_mtval;
        mpie_q   <= mie_q;
        mie_q    <= 1'b0;
        pc_q     <= {mtvec_base_q, 2'b00};
      end else if (dec_mret) begin
        pc_q   <= mepc_q;
        mie_q  <= mpie_q;
        mpie_q <= 1'b1;
      end else begin
        pc_q <= pc_next;
        if (csr_wen) begin
          case (csr_addr)
            12'h300: begin
              mie_q  <= csr_wdata_pre[3];
              mpie_q <= csr_wdata_pre[7];
            end
            12'h304: begin
              msie_q <= csr_wdata_pre[3];
              mtie_q <= csr_wdata_pre[7];
              meie_q <= csr_wdata_pre[11];
            end
            12'h305: mtvec_base_q <= csr_wdata_pre[31:2];
            12'h340: mscratch_q   <= csr_wdata_pre;
            12'h341: mepc_q       <= csr_wdata_pre;
            12'h342: mcause_q     <= csr_wdata_pre;
            12'h343: mtval_q      <= csr_wdata_pre;
            default: begin end // read-only CSRs cannot reach here (illegal)
          endcase
        end
      end
      if (retired)
        minstret_q <= minstret_q + 32'd1;
    end
  end

  // ------------------------------------------------------------------
  // Sequential: integer register file
  // ------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      for (int i = 0; i < 32; i = i + 1)
        rf[i] <= 32'h0;
    end else if (retired && rd_wen && (rd != 5'd0)) begin
      rf[rd] <= rd_wdata;
    end
  end

  // ------------------------------------------------------------------
  // Debug outputs
  // ------------------------------------------------------------------
  assign dbg_pc          = pc_q;
  assign dbg_instr_valid = retired;
  assign dbg_trap_taken  = trap_taken;
  assign dbg_mcause      = trap_taken ? trap_cause : 32'h0;

endmodule
