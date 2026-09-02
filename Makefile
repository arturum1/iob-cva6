# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# ==============================================================================
# IOb-CVA6 Makefile
# ==============================================================================
# This Makefile regenerates the plain-Verilog sources in hardware/src/
# by combining:
#   - IObundle-specific SystemVerilog sources in hardware/sv/
#     (the CPU wrapper and the 32-bit AXI / config packages)
#   - Upstream OpenHWGroup CVA6 SystemVerilog sources from the
#     submodules/cva6/ submodule.
# All SV is converted to plain Verilog with sv2v so Quartus (and other
# downstream tools) can ingest it as Verilog-2001.
#
# Layout:
#   hardware/sv/      IObundle-specific .sv / .svh sources (committed
#                     in git, edited by hand).
#   hardware/src/     Generated .v files (overwritten by `make`). The
#                     py2hwsw build copies these into the project
#                     build directory.
#   submodules/cva6/  Upstream OpenHWGroup CVA6 (git submodule).
#
# Usage:
#   make                # default target: cva6 (convert SV -> Verilog)
#   make cva6           # explicit
#   make -B cva6        # force re-run
#
# Dependencies:
#   - sv2v (provided by the included shell.nix; if sv2v is not in
#     PATH the Makefile will re-invoke itself inside nix-shell
#     automatically)
#   - The CVA6 submodule: `git submodule update --init --recursive`
# ==============================================================================

SV2V ?= sv2v

# Where everything lives (absolute paths so the recipe is robust
# against `cd` in subshells).
CVA6_ROOT     := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CVA6_SUB      := $(CVA6_ROOT)/submodules/cva6
CVA6_IOB_SV   := $(CVA6_ROOT)/hardware/sv
CVA6_SRC_DIR  := $(CVA6_ROOT)/hardware/src
CVA6_STAGE    := $(CVA6_ROOT)/hardware/src_sv2v_stage

# ==============================================================================
# Upstream CVA6 source manifest.
# ==============================================================================
# This is the complete synthesizable RTL set for the rv32imac + Sv32 MMU +
# HPDCACHE_WT (16K I$ + 32K D$) configuration, mirroring the upstream
# core/Flist.cva6 + core/cache_subsystem/hpdcache/rtl/hpdcache.Flist minus
# the FPU (cvfpu), cvxif-example, and accelerator files, which are all
# gated off by this configuration (RVF/RVD=0, CvxifEn=0, EnableAccelerator=0).
#
# NOTE: the upstream `cv32a6_imac_sv32_config_pkg.sv` is intentionally NOT
# included: its package is also named `cva6_config_pkg` and would collide
# with the IOb-specific `hardware/sv/cva6_config_pkg.sv`, which is a
# faithful copy with the 32-bit AXI / IOb memory-region overrides.
# ==============================================================================

HPDCACHE_DIR := $(CVA6_SUB)/core/cache_subsystem/hpdcache

# Packages (base CVA6 + PULP `axi_pkg`; note: no ${TARGET_CFG}_config_pkg.sv,
# see the NOTE above).
CVA6_UPSTREAM_PKGS := \
    $(CVA6_SUB)/core/include/config_pkg.sv \
    $(CVA6_SUB)/core/include/riscv_pkg.sv \
    $(CVA6_SUB)/core/include/ariane_pkg.sv \
    $(CVA6_SUB)/core/include/build_config_pkg.sv \
    $(CVA6_SUB)/core/include/instr_tracer_pkg.sv \
    $(CVA6_SUB)/core/include/wt_cache_pkg.sv \
    $(CVA6_SUB)/core/include/std_cache_pkg.sv \
    $(CVA6_SUB)/core/include/aes_pkg.sv \
    $(CVA6_SUB)/core/include/triggers_pkg.sv \
    $(CVA6_SUB)/core/include/dummy_l15_pkg.sv \
    $(CVA6_SUB)/corev_apu/tb/ariane_axi_pkg.sv \
    $(CVA6_SUB)/vendor/pulp-platform/axi/src/axi_pkg.sv

# FPGA-support single/dual-port RAM cells (used by frontend BTB/BHT and
# cva6_fifo_v3).
CVA6_UPSTREAM_FPGA_RAM := \
    $(CVA6_SUB)/vendor/pulp-platform/fpga-support/rtl/SyncDpRam.sv \
    $(CVA6_SUB)/vendor/pulp-platform/fpga-support/rtl/AsyncDpRam.sv \
    $(CVA6_SUB)/vendor/pulp-platform/fpga-support/rtl/AsyncThreePortRam.sv \
    $(CVA6_SUB)/vendor/pulp-platform/fpga-support/rtl/SyncThreePortRam.sv \
    $(CVA6_SUB)/vendor/pulp-platform/fpga-support/rtl/SyncDpRam_ind_r_w.sv

# PULP common cells (fifo_v3, arbiter/mux/demux, lzc, etc.).
CVA6_UPSTREAM_COMMON_CELLS := \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/cf_math_pkg.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/fifo_v3.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/lfsr.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/lfsr_8bit.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/stream_arbiter.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/stream_arbiter_flushable.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/stream_mux.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/stream_demux.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/lzc.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/rr_arb_tree.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/shift_reg.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/unread.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/popcount.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/exp_backoff.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/counter.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/delta_counter.sv

# CVA6 top modules: the RISC-V core (cva6) and the ariane wrapper.
CVA6_UPSTREAM_TOPS := \
    $(CVA6_SUB)/core/cva6.sv \
    $(CVA6_SUB)/corev_apu/src/ariane.sv

# Core RTL (everything under core/*.sv) minus the files that only matter
# for configurations this build does not use: the FPU wrapper (RVF/RVD=0),
# the cvxif interface/example drivers (CvxifEn=0) and the accelerator
# stub / dispatcher (EnableAccelerator=0). cva6.sv is listed separately
# above, so prune it here to avoid a duplicate.
CVA6_UPSTREAM_CORE_EXCL := \
    $(CVA6_SUB)/core/cva6.sv \
    $(CVA6_SUB)/core/fpu_wrap.sv \
    $(CVA6_SUB)/core/acc_dispatcher.sv \
    $(CVA6_SUB)/core/cva6_accel_first_pass_decoder_stub.sv \
    $(CVA6_SUB)/core/cvxif_fu.sv \
    $(CVA6_SUB)/core/cvxif_compressed_if_driver.sv \
    $(CVA6_SUB)/core/cvxif_issue_register_commit_if_driver.sv
CVA6_UPSTREAM_CORE := \
    $(filter-out $(CVA6_UPSTREAM_CORE_EXCL), $(wildcard $(CVA6_SUB)/core/*.sv))

# Subsystem RTL: frontend, cache subsystem, PMP, MMU.
CVA6_UPSTREAM_FRONTEND := $(wildcard $(CVA6_SUB)/core/frontend/*.sv)
CVA6_UPSTREAM_CACHE   := $(wildcard $(CVA6_SUB)/core/cache_subsystem/*.sv)
CVA6_UPSTREAM_PMP     := $(wildcard $(CVA6_SUB)/core/pmp/src/*.sv)
CVA6_UPSTREAM_MMU     := $(wildcard $(CVA6_SUB)/core/cva6_mmu/*.sv)

# Behavioral SRAM models used by the icache / shared TLB / tracer.
CVA6_UPSTREAM_SRAM := \
    $(CVA6_SUB)/vendor/pulp-platform/tech_cells_generic/src/rtl/tc_sram.sv \
    $(CVA6_SUB)/common/local/util/sram.sv \
    $(CVA6_SUB)/common/local/util/sram_cache.sv \
    $(CVA6_SUB)/common/local/util/tc_sram_wrapper.sv \
    $(CVA6_SUB)/common/local/util/tc_sram_wrapper_cache_techno.sv

# RVFI instruction tracer (instantiated unconditionally in cva6.sv).
CVA6_UPSTREAM_TRACER := \
    $(CVA6_SUB)/common/local/util/instr_tracer.sv

# HPD cache (cv-hpdcache submodule). Follows rtl/hpdcache.Flist; the
# SRAM macros come from the behavioural variants (Quartus infer block
# RAMs from them). The rtl/src/target/* adapters and the L15 utilities
# (hpdcache_*l15*) are for other SoC integration paths (L15 NOC) and
# are not instantiated with the AXI4-ATOP NOC used here.
CVA6_UPSTREAM_HPD_EXCL := \
    $(HPDCACHE_DIR)/rtl/src/utils/hpdcache_to_l15.sv \
    $(HPDCACHE_DIR)/rtl/src/utils/hpdcache_l15_req_arbiter.sv \
    $(HPDCACHE_DIR)/rtl/src/utils/hpdcache_l15_resp_demux.sv
CVA6_UPSTREAM_HPD := \
    $(filter-out $(CVA6_UPSTREAM_HPD_EXCL), \
        $(wildcard $(HPDCACHE_DIR)/rtl/src/*.sv) \
        $(wildcard $(HPDCACHE_DIR)/rtl/src/utils/*.sv) \
        $(wildcard $(HPDCACHE_DIR)/rtl/src/common/*.sv) \
        $(wildcard $(HPDCACHE_DIR)/rtl/src/hwpf_stride/*.sv) \
        $(HPDCACHE_DIR)/rtl/src/common/macros/behav/hpdcache_sram_1rw.sv \
        $(HPDCACHE_DIR)/rtl/src/common/macros/behav/hpdcache_sram_wbyteenable_1rw.sv \
        $(HPDCACHE_DIR)/rtl/src/common/macros/behav/hpdcache_sram_wmask_1rw.sv)

# All upstream sources (unique basenames guaranteed when flattened into
# the staging dir).
CVA6_UPSTREAM_SV := \
    $(CVA6_UPSTREAM_PKGS) \
    $(CVA6_UPSTREAM_FPGA_RAM) \
    $(CVA6_UPSTREAM_COMMON_CELLS) \
    $(CVA6_UPSTREAM_TOPS) \
    $(CVA6_UPSTREAM_CORE) \
    $(CVA6_UPSTREAM_FRONTEND) \
    $(CVA6_UPSTREAM_CACHE) \
    $(CVA6_UPSTREAM_PMP) \
    $(CVA6_UPSTREAM_MMU) \
    $(CVA6_UPSTREAM_SRAM) \
    $(CVA6_UPSTREAM_TRACER) \
    $(CVA6_UPSTREAM_HPD)

# Upstream .svh headers (cva6.sv and ariane.sv `include these). sv2v
# resolves them from the -I search path; we don't need to copy them
# into the staging dir, but we still list them here so the user can see
# what sv2v needs to find.
CVA6_UPSTREAM_SVH := \
    $(CVA6_SUB)/core/include/cvxif_types.svh \
    $(CVA6_SUB)/core/include/rvfi_types.svh

# IObundle-specific sources. These live in hardware/sv/ (committed):
# cva6_wrapper.sv (the ariane black-box wrapper), cva6_config_pkg.sv
# (self-contained 32-bit config; replaces upstream ${TARGET_CFG}_config_pkg.sv)
# and the rvfi_types.svh copy.
CVA6_IOB_SOURCES := $(wildcard $(CVA6_IOB_SV)/*.sv) $(wildcard $(CVA6_IOB_SV)/*.svh)

# sv2v include paths. The upstream CVA6 sources `include files from
# these directories; we pass them all so sv2v can resolve them. The
# staging dir is first so the just-copied files win if there is a name
# collision (there shouldn't be).
CVA6_SV2V_INCDIR := \
    -I $(CVA6_STAGE) \
    -I $(CVA6_IOB_SV) \
    -I $(CVA6_SUB)/core/include \
    -I $(CVA6_SUB)/vendor/pulp-platform/axi/include \
    -I $(CVA6_SUB)/vendor/pulp-platform/common_cells/include \
    -I $(CVA6_SUB)/vendor/pulp-platform/common_cells/src \
    -I $(CVA6_SUB)/common/local/util \
    -I $(HPDCACHE_DIR)/rtl/include

# Define the IOb-CVA6 conf.vh macros at the command line so the
# conversion doesn't need the conf.vh file (which is project-specific
# and lives in the project build dir, not in this source dir).
# `VERILATOR` skips the struct-`/class-based RVFI trace formatting in
# instr_tracer.sv / ex_trace_item.svh / instr_trace_item.svh (which is
# simulation-only code guarded by `ifndef VERILATOR`).
CVA6_SV2V_DEFINES := \
    -D VERILATOR \
    -D IOB_SYSTEM_LINUX_IOB_CVA6_RESET_VECTOR=32\'h40000000 \
    -D IOB_SYSTEM_LINUX_IOB_CVA6_IO_REGION_BASE=32\'h80000000 \
    -D IOB_SYSTEM_LINUX_IOB_CVA6_IO_REGION_SIZE=32\'h40000000

.PHONY: cva6 convert-sv2v
cva6 convert-sv2v:
	@if ! command -v $(SV2V) >/dev/null 2>&1; then \
	    if [ -f "$(CVA6_ROOT)/shell.nix" ]; then \
	        echo "$(SV2V) not found in PATH, re-invoking inside nix-shell ..."; \
	        exec nix-shell --run "$(MAKE) $(MAKECMDGOALS)"; \
	    else \
	        echo "ERROR: $(SV2V) not found in PATH and no shell.nix found."; \
	        exit 1; \
	    fi; \
	fi
	@if [ ! -f "$(CVA6_SUB)/core/cva6.sv" ]; then \
	    echo "ERROR: CVA6 submodule not initialised."; \
	    echo "  Run: git submodule update --init --recursive"; \
	    exit 1; \
	fi
	@if [ -z "$(wildcard $(CVA6_IOB_SV)/*.sv)" ]; then \
	    echo "ERROR: no IObundle-specific sources in $(CVA6_IOB_SV)/."; \
	    echo "  Expected at least cva6_wrapper.sv, cva6_config_pkg.sv,"; \
	    echo "  cva6_axi_pkg.sv."; \
	    exit 1; \
	fi
	@echo "=== Stage 1/3: copy sources to $(CVA6_STAGE)/ ==="
	@rm -rf $(CVA6_STAGE)
	@mkdir -p $(CVA6_STAGE)
	@cp -f $(CVA6_UPSTREAM_SV) $(CVA6_STAGE)/
	@cp -f $(CVA6_UPSTREAM_SVH) $(CVA6_STAGE)/
	@cp -f $(CVA6_IOB_SOURCES) $(CVA6_STAGE)/
	@echo "  Copied $$(ls -1 $(CVA6_STAGE) | wc -l) files"
	@echo ""
	@echo "=== Stage 2/3: convert .sv -> .v via $(SV2V) ==="
	@echo "  NOTE: this stage is single-threaded and can take 30-40 min"
	@echo "  on the full CVA6 source set -- please be patient."
	@echo "  (packages must be elaborated together in a single sv2v call)"
	@cd $(CVA6_STAGE) && \
	rm -rf $(CVA6_STAGE)/.sv2v_cache && \
	$(SV2V) $(CVA6_SV2V_INCDIR) $(CVA6_SV2V_DEFINES) -w $(CVA6_STAGE) *.sv && \
	rm -f $(CVA6_STAGE)/*.sv $(CVA6_STAGE)/*.svh
	@echo "  Converted $$(ls -1 $(CVA6_STAGE)/*.v 2>/dev/null | wc -l) files"
	@echo ""
	@echo "=== Stage 3/3: replace hardware/src/ with the converted .v files ==="
	@rm -f $(CVA6_SRC_DIR)/*.sv $(CVA6_SRC_DIR)/*.svh $(CVA6_SRC_DIR)/*.v
	@cp -f $(CVA6_STAGE)/*.v $(CVA6_SRC_DIR)/
	@rm -rf $(CVA6_STAGE)
	@echo "  hardware/src/ now contains:"
	@ls -1 $(CVA6_SRC_DIR)/*.v | sed 's/^/    /'
	@echo ""
	@echo "Next step: run your py2hwsw build (e.g. 'make' in the"
	@echo "project dir) so the .v files are copied to the build"
	@echo "directory and Quartus picks them up via VSRC."

.PHONY: clean
clean:
	@echo "Removing generated .v files from $(CVA6_SRC_DIR)/"
	@rm -f $(CVA6_SRC_DIR)/*.v
	@rm -f $(CVA6_STAGE)/*

.PHONY: clean-submodules
clean-submodules:
	git submodule foreach --recursive git clean -ffdx

.PHONY: cva6 convert-sv2v clean clean-submodules
# Default target.
.DEFAULT_GOAL := cva6
