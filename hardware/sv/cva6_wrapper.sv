// SPDX-FileCopyrightText: 2025 IObundle
//
// SPDX-License-Identifier: MIT
//
// IOb-CVA6 wrapper (SystemVerilog).
//
// This file is hand-written and is the *real* wrapper that instantiates
// the CVA6 `ariane` module. It is referenced from the py2hwsw-generated
// `cva6.v` shim as a black box.
//
// Reason this lives in a .sv file (not the py2hwsw snippet): the
// py2hwsw framework emits its module body as Verilog-2001 (.v), which
// does not understand `pkg::member` or packed-struct member access.
// CVA6 is SystemVerilog, so the wrapper has to be SystemVerilog too.
//
// The reset vector and IO-region macros (RESET_VECTOR, IO_REGION_BASE,
// IO_REGION_SIZE) are passed to sv2v via the -D flag when running
// `make convert-sv2v`. The py2hwsw-generated conf.vh (which lives in
// the project build dir, not in this source dir) is NOT included here
// because sv2v can't find it. At Quartus compile time, the top-level
// cva6.v still includes the conf.vh, so the
// macros are available globally and the `ifndef` fallbacks in
// cva6_config_pkg.sv pick up the conf.vh values (overriding the
// sv2v-baked defaults).

`ifndef IOB_CVA6_RESET_VECTOR
`define IOB_CVA6_RESET_VECTOR 32'h40000000
`endif

module cva6_wrapper #(
    parameter int AXI_ID_W   = 4,
    parameter int AXI_ADDR_W = 32,
    parameter int AXI_DATA_W = 32,
    parameter int AXI_LEN_W  = 4
) (
    // IOb-SoC clock/reset bundle
    input logic clk_i,
    input logic cke_i,
    input logic arst_i,
    input logic rst_i,

    // Instruction AXI bus (TIE-OFF: not driven)
    output logic                      ibus_axi_arvalid_o,
    input  logic                      ibus_axi_arready_i,
    output logic [    AXI_ADDR_W-1:0] ibus_axi_araddr_o,
    output logic [      AXI_ID_W-1:0] ibus_axi_arid_o,
    output logic [     AXI_LEN_W-1:0] ibus_axi_arlen_o,
    output logic [               2:0] ibus_axi_arsize_o,
    output logic [               1:0] ibus_axi_arburst_o,
    output logic                      ibus_axi_arlock_o,
    output logic [               3:0] ibus_axi_arcache_o,
    output logic [               3:0] ibus_axi_arqos_o,
    output logic [               2:0] ibus_axi_arprot_o,
    output logic [               3:0] ibus_axi_arregion_o,
    input  logic                      ibus_axi_rvalid_i,
    output logic                      ibus_axi_rready_o,
    input  logic [    AXI_DATA_W-1:0] ibus_axi_rdata_i,
    input  logic [      AXI_ID_W-1:0] ibus_axi_rid_i,
    input  logic [               1:0] ibus_axi_rresp_i,
    input  logic                      ibus_axi_rlast_i,
    output logic                      ibus_axi_awvalid_o,
    input  logic                      ibus_axi_awready_i,
    output logic [    AXI_ADDR_W-1:0] ibus_axi_awaddr_o,
    output logic [      AXI_ID_W-1:0] ibus_axi_awid_o,
    output logic [     AXI_LEN_W-1:0] ibus_axi_awlen_o,
    output logic [               2:0] ibus_axi_awsize_o,
    output logic [               1:0] ibus_axi_awburst_o,
    output logic                      ibus_axi_awlock_o,
    output logic [               3:0] ibus_axi_awcache_o,
    output logic [               3:0] ibus_axi_awqos_o,
    output logic [               2:0] ibus_axi_awprot_o,
    output logic [               3:0] ibus_axi_awregion_o,
    output logic                      ibus_axi_wvalid_o,
    input  logic                      ibus_axi_wready_i,
    output logic [    AXI_DATA_W-1:0] ibus_axi_wdata_o,
    output logic [(AXI_DATA_W/8)-1:0] ibus_axi_wstrb_o,
    output logic                      ibus_axi_wlast_o,
    input  logic                      ibus_axi_bvalid_i,
    output logic                      ibus_axi_bready_o,
    input  logic [      AXI_ID_W-1:0] ibus_axi_bid_i,
    input  logic [               1:0] ibus_axi_bresp_i,

    // Data AXI bus (DRIVEN: carries the entire CVA6 NoC master)
    output logic                      dbus_axi_arvalid_o,
    input  logic                      dbus_axi_arready_i,
    output logic [    AXI_ADDR_W-1:0] dbus_axi_araddr_o,
    output logic [      AXI_ID_W-1:0] dbus_axi_arid_o,
    output logic [     AXI_LEN_W-1:0] dbus_axi_arlen_o,
    output logic [               2:0] dbus_axi_arsize_o,
    output logic [               1:0] dbus_axi_arburst_o,
    output logic                      dbus_axi_arlock_o,
    output logic [               3:0] dbus_axi_arcache_o,
    output logic [               3:0] dbus_axi_arqos_o,
    output logic [               2:0] dbus_axi_arprot_o,
    output logic [               3:0] dbus_axi_arregion_o,
    input  logic                      dbus_axi_rvalid_i,
    output logic                      dbus_axi_rready_o,
    input  logic [    AXI_DATA_W-1:0] dbus_axi_rdata_i,
    input  logic [      AXI_ID_W-1:0] dbus_axi_rid_i,
    input  logic [               1:0] dbus_axi_rresp_i,
    input  logic                      dbus_axi_rlast_i,
    output logic                      dbus_axi_awvalid_o,
    input  logic                      dbus_axi_awready_i,
    output logic [    AXI_ADDR_W-1:0] dbus_axi_awaddr_o,
    output logic [      AXI_ID_W-1:0] dbus_axi_awid_o,
    output logic [     AXI_LEN_W-1:0] dbus_axi_awlen_o,
    output logic [               2:0] dbus_axi_awsize_o,
    output logic [               1:0] dbus_axi_awburst_o,
    output logic                      dbus_axi_awlock_o,
    output logic [               3:0] dbus_axi_awcache_o,
    output logic [               3:0] dbus_axi_awqos_o,
    output logic [               2:0] dbus_axi_awprot_o,
    output logic [               3:0] dbus_axi_awregion_o,
    output logic                      dbus_axi_wvalid_o,
    input  logic                      dbus_axi_wready_i,
    output logic [    AXI_DATA_W-1:0] dbus_axi_wdata_o,
    output logic [(AXI_DATA_W/8)-1:0] dbus_axi_wstrb_o,
    output logic                      dbus_axi_wlast_o,
    input  logic                      dbus_axi_bvalid_i,
    output logic                      dbus_axi_bready_o,
    input  logic [      AXI_ID_W-1:0] dbus_axi_bid_i,
    input  logic [               1:0] dbus_axi_bresp_i,

    // Interrupt bundle
    input logic msip_i,
    input logic mtip_i,
    input logic meip_i,
    input logic seip_i,

    // Timebase
    input logic [63:0] mtime_i
);

  // ----------------------------------------------------------------
  // cva6_cfg_t (32-bit AXI, IO region split, Linux-capable base)
  // ----------------------------------------------------------------
  // cva6_config_pkg::cva6_cfg is a cva6_user_cfg_t; we hand it
  // to build_config_pkg::build_config() to materialise the full
  // cva6_cfg_t that cva6.sv and ariane.sv consume.
  localparam config_pkg::cva6_cfg_t Cva6Cfg = build_config_pkg::build_config(
      cva6_config_pkg::cva6_cfg
  );

  // ----------------------------------------------------------------
  // ariane wrapper signals (32-bit AXI4)
  // ----------------------------------------------------------------
  // ariane_axi is the upstream AXI package that ariane.sv parameterises
  // its NoC master with. Its widths come from
  // cva6_config_pkg::CVA6ConfigAxi* (overridden to 32-bit in
  // cva6_config_pkg.sv), so req_t/resp_t/aw_chan_t/... are all 32-bit.
  ariane_axi::req_t noc_req;
  ariane_axi::resp_t noc_resp;

  // ----------------------------------------------------------------
  // Reset combination
  // ----------------------------------------------------------------
  // IOb-SoC provides arst_i (asynchronous, active-high) and rst_i
  // (synchronous, active-high). CVA6 expects a single asynchronous
  // active-low reset. Combine them with logical-OR (either reset
  // source holds the CPU in reset) and invert.
  logic rst_ni;
  assign rst_ni = ~(arst_i | rst_i);

  // cke_i (clock enable) is unused - CVA6 has no clock-enable port.
  logic unused_cke;
  assign unused_cke = ^cke_i;

  // ----------------------------------------------------------------
  // ariane instantiation (the CVA6 top)
  // ----------------------------------------------------------------
  ariane #(
      .CVA6Cfg   (Cva6Cfg),
      .noc_req_t (ariane_axi::req_t),
      .noc_resp_t(ariane_axi::resp_t)
  ) i_ariane (
      .clk_i        (clk_i),
      .rst_ni       (rst_ni),
      .boot_addr_i  (`IOB_CVA6_RESET_VECTOR),
      .hart_id_i    (32'h0),
      // CVA6 irq_i mapping (csr_regfile.sv:2028, :2679):
      //   irq_i[0] -> mip.MEIP (machine external)
      //   irq_i[1] -> mip.SEIP (supervisor external, when RVS=1)
      // msip_i is consumed by the memory-mapped CLINT, not by this port.
      .irq_i        ({seip_i, meip_i}),
      .ipi_i        (1'b0),
      .time_irq_i   (mtip_i),
      .debug_req_i  (1'b0),
      .rvfi_probes_o(),
      .noc_req_o    (noc_req),
      .noc_resp_i   (noc_resp)
  );

  // ----------------------------------------------------------------
  // ariane NoC -> iob-system dBus (AXI4-ATOP)
  // ----------------------------------------------------------------
  // AR channel
  assign dbus_axi_arvalid_o  = noc_req.ar_valid;
  assign dbus_axi_araddr_o   = noc_req.ar.addr;
  assign dbus_axi_arid_o     = noc_req.ar.id;
  assign dbus_axi_arlen_o    = noc_req.ar.len[AXI_LEN_W-1:0];
  assign dbus_axi_arsize_o   = noc_req.ar.size;
  assign dbus_axi_arburst_o  = noc_req.ar.burst;
  assign dbus_axi_arlock_o   = noc_req.ar.lock;
  assign dbus_axi_arcache_o  = noc_req.ar.cache;
  assign dbus_axi_arqos_o    = noc_req.ar.qos;
  assign dbus_axi_arprot_o   = noc_req.ar.prot;
  assign dbus_axi_arregion_o = noc_req.ar.region;
  assign noc_resp.ar_ready   = dbus_axi_arready_i;

  // R channel
  assign dbus_axi_rready_o   = noc_req.r_ready;
  assign noc_resp.r_valid    = dbus_axi_rvalid_i;
  assign noc_resp.r.id       = dbus_axi_rid_i;
  assign noc_resp.r.data     = dbus_axi_rdata_i;
  assign noc_resp.r.resp     = dbus_axi_rresp_i;
  assign noc_resp.r.last     = dbus_axi_rlast_i;
  assign noc_resp.r.user     = '0;

  // AW channel
  assign dbus_axi_awvalid_o  = noc_req.aw_valid;
  assign dbus_axi_awaddr_o   = noc_req.aw.addr;
  assign dbus_axi_awid_o     = noc_req.aw.id;
  assign dbus_axi_awlen_o    = noc_req.aw.len[AXI_LEN_W-1:0];
  assign dbus_axi_awsize_o   = noc_req.aw.size;
  assign dbus_axi_awburst_o  = noc_req.aw.burst;
  assign dbus_axi_awlock_o   = noc_req.aw.lock;
  assign dbus_axi_awcache_o  = noc_req.aw.cache;
  assign dbus_axi_awqos_o    = noc_req.aw.qos;
  assign dbus_axi_awprot_o   = noc_req.aw.prot;
  assign dbus_axi_awregion_o = noc_req.aw.region;
  assign noc_resp.aw_ready   = dbus_axi_awready_i;

  // W channel
  assign dbus_axi_wvalid_o   = noc_req.w_valid;
  assign dbus_axi_wdata_o    = noc_req.w.data;
  assign dbus_axi_wstrb_o    = noc_req.w.strb;
  assign dbus_axi_wlast_o    = noc_req.w.last;
  assign noc_resp.w_ready    = dbus_axi_wready_i;

  // B channel
  assign dbus_axi_bready_o   = noc_req.b_ready;
  assign noc_resp.b_valid    = dbus_axi_bvalid_i;
  assign noc_resp.b.id       = dbus_axi_bid_i;
  assign noc_resp.b.resp     = dbus_axi_bresp_i;
  assign noc_resp.b.user     = '0;

  // ----------------------------------------------------------------
  // iBus tie-off (no requests)
  // ----------------------------------------------------------------
  assign ibus_axi_arvalid_o  = 1'b0;
  assign ibus_axi_araddr_o   = {AXI_ADDR_W{1'b0}};
  assign ibus_axi_arid_o     = {AXI_ID_W{1'b0}};
  assign ibus_axi_arlen_o    = {AXI_LEN_W{1'b0}};
  assign ibus_axi_arsize_o   = 3'b0;
  assign ibus_axi_arburst_o  = 2'b0;
  assign ibus_axi_arlock_o   = 1'b0;
  assign ibus_axi_arcache_o  = 4'b0;
  assign ibus_axi_arqos_o    = 4'b0;
  assign ibus_axi_arprot_o   = 3'b0;
  assign ibus_axi_arregion_o = 4'b0;
  assign ibus_axi_rready_o   = 1'b0;
  assign ibus_axi_awvalid_o  = 1'b0;
  assign ibus_axi_awaddr_o   = {AXI_ADDR_W{1'b0}};
  assign ibus_axi_awid_o     = {AXI_ID_W{1'b0}};
  assign ibus_axi_awlen_o    = {AXI_LEN_W{1'b0}};
  assign ibus_axi_awsize_o   = 3'b0;
  assign ibus_axi_awburst_o  = 2'b0;
  assign ibus_axi_awlock_o   = 1'b0;
  assign ibus_axi_awcache_o  = 4'b0;
  assign ibus_axi_awqos_o    = 4'b0;
  assign ibus_axi_awprot_o   = 3'b0;
  assign ibus_axi_awregion_o = 4'b0;
  assign ibus_axi_wvalid_o   = 1'b0;
  assign ibus_axi_wdata_o    = {AXI_DATA_W{1'b0}};
  assign ibus_axi_wstrb_o    = {(AXI_DATA_W / 8) {1'b0}};
  assign ibus_axi_wlast_o    = 1'b0;
  assign ibus_axi_bready_o   = 1'b0;

  // mtime_i is consumed at the SoC level by an iob_clint; CVA6 itself
  // reads mtime via MMIO + SBI trap, so we deliberately leave it
  // dangling inside the wrapper.
  logic unused_mtime;
  assign unused_mtime = ^mtime_i;

endmodule

