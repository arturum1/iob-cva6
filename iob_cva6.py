# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

import os


def setup(py_params_dict):
    # Each generated cpu verilog module must have a unique name due to different python parameters
    # (can't have two different verilog modules with same name).
    assert "name" in py_params_dict, print(
        "Error: Missing name for generated cva6 module."
    )

    # ------------------------------------------------------------------
    # User-facing parameters
    # ------------------------------------------------------------------
    # Defaults match the iob_cva6 Makefile. `reset_addr` is forwarded to
    # the CVA6 `boot_addr_i` port. The IO/uncached region is wired into
    # the CVA6 cva6_cfg_t in `hardware/src/iob_cva6_config_pkg.sv` (the
    # same package is referenced from the snippet below). To change the
    # region, edit iob_cva6_config_pkg.sv and rebuild.
    params = {
        "reset_addr": 0x40000000,  # RESET_VECTOR
        "io_region_base": 0x80000000,  # IO_REGION_BASE
        "io_region_size": 0x40000000,  # IO_REGION_SIZE
    }
    for param in py_params_dict:
        if param in params:
            params[param] = py_params_dict[param]

    attributes_dict = {
        "name": py_params_dict["name"],
        "version": "0.2.0",
        "generate_hw": True,
        "confs": [
            {
                "name": "AXI_ID_W",
                "descr": "AXI ID bus width",
                "type": "P",
                "val": 4,
                "min": 1,
                "max": 32,
            },
            {
                "name": "AXI_ADDR_W",
                "descr": "AXI address bus width",
                "type": "P",
                "val": 32,
                "min": 1,
                "max": 64,
            },
            {
                "name": "AXI_DATA_W",
                "descr": "AXI data bus width",
                "type": "P",
                "val": 32,
                "min": 32,
                "max": 128,
            },
            {
                "name": "AXI_LEN_W",
                "descr": "AXI burst length width (AxLEN is 8 bits internally; "
                "we expose the low AXI_LEN_W bits to the SoC)",
                "type": "P",
                "val": 4,
                "min": 1,
                "max": 8,
            },
            {
                "name": "RESET_VECTOR",
                "descr": "CVA6 reset vector (boot_addr_i). Forwarded to the "
                "iob_cva6_wrapper.sv as a 32-bit hex literal via a "
                "`define in the conf.vh.",
                "type": "D",
                "val": f"32'h{params['reset_addr'] & 0xFFFFFFFF:08x}",
            },
            {
                "name": "IO_REGION_BASE",
                "descr": "CVA6 non-idempotent (IO) region base. Forwarded to "
                "the iob_cva6_config_pkg.sv as a 32-bit hex literal "
                "via a `define in the conf.vh.",
                "type": "D",
                "val": f"32'h{params['io_region_base'] & 0xFFFFFFFF:08x}",
            },
            {
                "name": "IO_REGION_SIZE",
                "descr": "CVA6 non-idempotent (IO) region size. Forwarded to "
                "the iob_cva6_config_pkg.sv as a 32-bit hex literal "
                "via a `define in the conf.vh.",
                "type": "D",
                "val": f"32'h{params['io_region_size'] & 0xFFFFFFFF:08x}",
            },
        ],
        # ------------------------------------------------------------------
        # Ports exposed to the IOb-SoC
        # ------------------------------------------------------------------
        # The wrapper is configured for **one CVA6 NoC master**, driven
        # out of `d_bus_m`. The IOb-SoC contract requires both `i_bus_m`
        # and `d_bus_m` ports; we tie `i_bus_m` to zero (no requests) so
        # the crossbar treats that subordinate as idle, and let
        # `d_bus_m` carry every load/store/fetch transaction. This is
        # the lowest-risk topology - CVA6 has no inherent instruction
        # vs data split on its NoC port, so duplicating it on two
        # separate SoC ports would buy nothing.
        "ports": [
            {
                "name": "clk_en_rst_s",
                "descr": "Clock, clock enable and reset",
                "signals": {"type": "iob_clk"},
            },
            {
                "name": "rst_i",
                "descr": "Synchronous reset (positive polarity, IOb-SoC convention)",
                "signals": [
                    {
                        "name": "rst_i",
                        "descr": "CPU synchronous reset",
                        "width": "1",
                    },
                ],
            },
            {
                "name": "i_bus_m",
                "descr": "Instruction AXI bus (TIE-OFF: not driven; the CVA6 "
                "core has a single NoC master which is routed to "
                "d_bus_m. Leave this subordinate idle.)",
                "signals": {
                    "type": "axi",
                    "prefix": "ibus_",
                    "ID_W": "AXI_ID_W",
                    "ADDR_W": "AXI_ADDR_W",
                    "DATA_W": "AXI_DATA_W",
                    "LEN_W": "AXI_LEN_W",
                    "LOCK_W": 1,
                },
            },
            {
                "name": "d_bus_m",
                "descr": "Data AXI bus (active: carries all CVA6 traffic - "
                "instruction fetches, loads, stores and atomics)",
                "signals": {
                    "type": "axi",
                    "prefix": "dbus_",
                    "ID_W": "AXI_ID_W",
                    "ADDR_W": "AXI_ADDR_W",
                    "DATA_W": "AXI_DATA_W",
                    "LEN_W": "AXI_LEN_W",
                    "LOCK_W": 1,
                },
            },
            {
                "name": "interrupt_i",
                "descr": "Standard RISC-V interrupt pending bits (machine + supervisor)",
                "signals": [
                    {
                        "name": "msip_i",
                        "descr": "Machine software interrupt.",
                        "width": "1",
                    },
                    {
                        "name": "mtip_i",
                        "descr": "Machine timer interrupt.",
                        "width": "1",
                    },
                    {
                        "name": "meip_i",
                        "descr": "Machine external interrupt.",
                        "width": "1",
                    },
                    {
                        "name": "seip_i",
                        "descr": "Supervisor external interrupt.",
                        "width": "1",
                    },
                ],
            },
            {
                "name": "timebase_i",
                "descr": "Timebase interface. CVA6 does not read mtime through a "
                "dedicated port; the mtime value is consumed by OpenSBI via "
                "a memory-mapped CLINT and by `rdtime` -> trap+MMIO. The "
                "64-bit bus is exported here so an external iob_clint can "
                "drive the system timer counter.",
                "signals": [
                    {
                        "name": "mtime_i",
                        "descr": "External 64-bit mtime counter",
                        "width": "64",
                    },
                ],
            },
        ],
        # ------------------------------------------------------------------
        # Internal wires
        # ------------------------------------------------------------------
        # The iBus tie-off uses one net to sink the (unused) read-data
        # bus. The dBus port has a similar issue: the CVA6 NoC port
        # doesn't expose some signals (arprot, awprot, etc.) that the
        # IOb-SoC AXI bus type expects; we generate the missing
        # signals with the wires below.
        "wires": [],
        "subblocks": [],
        # ------------------------------------------------------------------
        # Verilog snippet
        # ------------------------------------------------------------------
        # The actual CVA6 wrapper is a hand-written SystemVerilog module
        # `cva6_wrapper` in `hardware/src/iob_cva6_wrapper.sv`. It must
        # be in a `.sv` file because it instantiates the upstream
        # OpenHWGroup `ariane` / `cva6` modules and references
        # SystemVerilog packages (`config_pkg`, `build_config_pkg`,
        # `iob_cva6_config_pkg`, `iob_cva6_axi`).
        #
        # The py2hwsw framework emits the *body* of this Python module
        # as Verilog-2001 (file extension `.v`), which cannot parse SV
        # packages. To work around this, the snippet below is just a
        # thin shim that forwards all IOb-SoC ports to a black-box
        # instance of `cva6_wrapper` (defined in the .sv file). Quartus
        # resolves the cross-file reference at elaboration time.
        "snippets": [
            {
                "verilog_code": """
// Thin Verilog-2001 shim that instantiates the SystemVerilog
// `cva6_wrapper` module from iob_cva6_wrapper.sv. The py2hwsw
// framework writes this file as `.v` and would otherwise drop or
// mis-parse the SystemVerilog constructs that CVA6 requires.
cva6_wrapper #(
    .AXI_ID_W   (AXI_ID_W),
    .AXI_ADDR_W (AXI_ADDR_W),
    .AXI_DATA_W (AXI_DATA_W),
    .AXI_LEN_W  (AXI_LEN_W)
) i_cva6_wrapper (
    // Clock and reset
    .clk_i  (clk_i),
    .cke_i  (cke_i),
    .arst_i (arst_i),
    .rst_i  (rst_i),

    // Instruction AXI bus (TIE-OFF in the SV wrapper)
    .ibus_axi_arvalid_o  (ibus_axi_arvalid_o),
    .ibus_axi_arready_i  (ibus_axi_arready_i),
    .ibus_axi_araddr_o   (ibus_axi_araddr_o),
    .ibus_axi_arid_o     (ibus_axi_arid_o),
    .ibus_axi_arlen_o    (ibus_axi_arlen_o),
    .ibus_axi_arsize_o   (ibus_axi_arsize_o),
    .ibus_axi_arburst_o  (ibus_axi_arburst_o),
    .ibus_axi_arlock_o   (ibus_axi_arlock_o),
    .ibus_axi_arcache_o  (ibus_axi_arcache_o),
    .ibus_axi_arqos_o    (ibus_axi_arqos_o),
    .ibus_axi_arprot_o   (ibus_axi_arprot_o),
    .ibus_axi_arregion_o (ibus_axi_arregion_o),
    .ibus_axi_rvalid_i   (ibus_axi_rvalid_i),
    .ibus_axi_rready_o   (ibus_axi_rready_o),
    .ibus_axi_rdata_i    (ibus_axi_rdata_i),
    .ibus_axi_rid_i      (ibus_axi_rid_i),
    .ibus_axi_rresp_i    (ibus_axi_rresp_i),
    .ibus_axi_rlast_i    (ibus_axi_rlast_i),
    .ibus_axi_awvalid_o  (ibus_axi_awvalid_o),
    .ibus_axi_awready_i  (ibus_axi_awready_i),
    .ibus_axi_awaddr_o   (ibus_axi_awaddr_o),
    .ibus_axi_awid_o     (ibus_axi_awid_o),
    .ibus_axi_awlen_o    (ibus_axi_awlen_o),
    .ibus_axi_awsize_o   (ibus_axi_awsize_o),
    .ibus_axi_awburst_o  (ibus_axi_awburst_o),
    .ibus_axi_awlock_o   (ibus_axi_awlock_o),
    .ibus_axi_awcache_o  (ibus_axi_awcache_o),
    .ibus_axi_awqos_o    (ibus_axi_awqos_o),
    .ibus_axi_awprot_o   (ibus_axi_awprot_o),
    .ibus_axi_awregion_o (ibus_axi_awregion_o),
    .ibus_axi_wvalid_o   (ibus_axi_wvalid_o),
    .ibus_axi_wready_i   (ibus_axi_wready_i),
    .ibus_axi_wdata_o    (ibus_axi_wdata_o),
    .ibus_axi_wstrb_o    (ibus_axi_wstrb_o),
    .ibus_axi_wlast_o    (ibus_axi_wlast_o),
    .ibus_axi_bvalid_i   (ibus_axi_bvalid_i),
    .ibus_axi_bready_o   (ibus_axi_bready_o),
    .ibus_axi_bid_i      (ibus_axi_bid_i),
    .ibus_axi_bresp_i    (ibus_axi_bresp_i),

    // Data AXI bus (DRIVEN from CVA6 NoC master)
    .dbus_axi_arvalid_o  (dbus_axi_arvalid_o),
    .dbus_axi_arready_i  (dbus_axi_arready_i),
    .dbus_axi_araddr_o   (dbus_axi_araddr_o),
    .dbus_axi_arid_o     (dbus_axi_arid_o),
    .dbus_axi_arlen_o    (dbus_axi_arlen_o),
    .dbus_axi_arsize_o   (dbus_axi_arsize_o),
    .dbus_axi_arburst_o  (dbus_axi_arburst_o),
    .dbus_axi_arlock_o   (dbus_axi_arlock_o),
    .dbus_axi_arcache_o  (dbus_axi_arcache_o),
    .dbus_axi_arqos_o    (dbus_axi_arqos_o),
    .dbus_axi_arprot_o   (dbus_axi_arprot_o),
    .dbus_axi_arregion_o (dbus_axi_arregion_o),
    .dbus_axi_rvalid_i   (dbus_axi_rvalid_i),
    .dbus_axi_rready_o   (dbus_axi_rready_o),
    .dbus_axi_rdata_i    (dbus_axi_rdata_i),
    .dbus_axi_rid_i      (dbus_axi_rid_i),
    .dbus_axi_rresp_i    (dbus_axi_rresp_i),
    .dbus_axi_rlast_i    (dbus_axi_rlast_i),
    .dbus_axi_awvalid_o  (dbus_axi_awvalid_o),
    .dbus_axi_awready_i  (dbus_axi_awready_i),
    .dbus_axi_awaddr_o   (dbus_axi_awaddr_o),
    .dbus_axi_awid_o     (dbus_axi_awid_o),
    .dbus_axi_awlen_o    (dbus_axi_awlen_o),
    .dbus_axi_awsize_o   (dbus_axi_awsize_o),
    .dbus_axi_awburst_o  (dbus_axi_awburst_o),
    .dbus_axi_awlock_o   (dbus_axi_awlock_o),
    .dbus_axi_awcache_o  (dbus_axi_awcache_o),
    .dbus_axi_awqos_o    (dbus_axi_awqos_o),
    .dbus_axi_awprot_o   (dbus_axi_awprot_o),
    .dbus_axi_awregion_o (dbus_axi_awregion_o),
    .dbus_axi_wvalid_o   (dbus_axi_wvalid_o),
    .dbus_axi_wready_i   (dbus_axi_wready_i),
    .dbus_axi_wdata_o    (dbus_axi_wdata_o),
    .dbus_axi_wstrb_o    (dbus_axi_wstrb_o),
    .dbus_axi_wlast_o    (dbus_axi_wlast_o),
    .dbus_axi_bvalid_i   (dbus_axi_bvalid_i),
    .dbus_axi_bready_o   (dbus_axi_bready_o),
    .dbus_axi_bid_i      (dbus_axi_bid_i),
    .dbus_axi_bresp_i    (dbus_axi_bresp_i),

    // Interrupts
    .msip_i (msip_i),
    .mtip_i (mtip_i),
    .meip_i (meip_i),
    .seip_i (seip_i),

    // Timebase
    .mtime_i (mtime_i)
);
"""
            }
        ],
    }

    # ------------------------------------------------------------------
    # Linter pragma
    # ------------------------------------------------------------------
    # `cva6.sv` (from the OpenHWGroup repo) triggers Verilator
    # UNUSEDSIGNAL warnings on hundreds of nets because the upstream
    # maintainers run the linter with non-default options. Silence the
    # noise in the iob-cva6 build.
    if py_params_dict.get("py2hwsw_target", "") == "setup":
        build_dir = py_params_dict.get("build_dir")
        os.makedirs(f"{build_dir}/hardware/lint/verilator", exist_ok=True)
        with open(f"{build_dir}/hardware/lint/verilator_config.vlt", "a") as file:
            file.write(
                f"""
// Lines generated by {os.path.basename(__file__)}
lint_off -file "*/cva6.sv"
lint_off -file "*/ariane.sv"
lint_off -file "*/cva6_wrapper.sv"
"""
            )

    return attributes_dict
