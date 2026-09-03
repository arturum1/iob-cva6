# SPDX-FileCopyrightText: 2025 IObundle
#
# SPDX-License-Identifier: MIT

# ==============================================================================
# IOb-CVA6 Makefile
# ==============================================================================
# This Makefile generates hardware/src/cva6.sv, a SINGLE self-contained
# SystemVerilog file that the IOb-SoC build consumes for the CVA6 core.
#
# Why a single file: the OpenHWGroup CVA6 RTL is a tree of interdependent
# packages + modules. Downstream tools (Vivado, Quartus, simulators) read
# sources in command-line order; a flat glob either cannot express
# "packages before modules" or orders them alphabetically, so a module can
# be read before the package it references in its port/parameter list
# (e.g. `[Synth 8-1031] ariane_pkg is not declared`). hardware/src/cva6.sv
# concatenates every source in dependency order -- all packages first
# (topologically sorted), then all modules -- and inlines every
# `` `include "x.svh" `` at its exact site, so there is no ordering and no
# include-path dependency left for the consuming tool.
#
# The merge is done by hardware/cva6_merge.py, which also emits a banner
# comment (``// FILE: <basename>``) before each concatenated source so the
# contents can be traced back to their origin file.
#
# This is the flat drop-in for synthesis:
#   - Vivado : read_verilog -sv hardware/src/cva6.sv  (+ top cva6_wrapper)
#   - Quartus: VERILOG_INPUT_VERSION SYSTEMVERILOG_2005, one source file
#   - Simulators / Verilator: elaborate hardware/src/cva6.sv
# No submodule include paths are required, and the VERILATOR macro is only
# needed if a particular simulator chokes on the SV classes in the
# instruction tracer (they sit inside `// pragma translate_off` for
# synthesis flows).
#
# Layout:
#   hardware/sv/      IObundle-specific sources (committed, hand-edited):
#                     cva6_config_pkg.sv, cva6_wrapper.sv (top), rvfi_types.svh.
#   hardware/src/     Generated: the single merged cva6.sv (overwritten by
#                     `make`). This is what the py2hwsw build consumes.
#   hardware/cva6_merge.py  The merge tool.
#   submodules/cva6/  Upstream OpenHWGroup CVA6 (git submodule).
#
# Usage:
#   make                # default target: cva6
#   make cva6           # explicit
#   make -B cva6        # force re-run
#   make clean          # remove the generated cva6.sv
#
# Dependencies:
#   - The CVA6 submodule: `git submodule update --init --recursive`
#   - python3 (used by hardware/cva6_merge.py)
# ==============================================================================

# Where everything lives (absolute paths so the recipe is robust
# against `cd` in subshells).
CVA6_ROOT     := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
CVA6_SUB      := $(CVA6_ROOT)/submodules/cva6
CVA6_IOB_SV   := $(CVA6_ROOT)/hardware/sv
CVA6_SRC_DIR  := $(CVA6_ROOT)/hardware/src

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
# for configurations this build does not use:
#   - fpu_wrap.sv: guarded by `if (CVA6Cfg.FpPresent)`. We set FpPresent=0
#     (RVF/RVD=0), so the synthesizer prunes the instantiation.
#   - acc_dispatcher.sv, cva6_accel_first_pass_decoder_stub.sv: guarded
#     by `if (CVA6Cfg.EnableAccelerator)`. We set EnableAccelerator=0.
#   - cvxif_fu.sv: the actual coprocessor body; with CvxifEn=COPRO_NONE
#     the cvxif_req/resp ports are tied off, no instance exists.
#   - cvxif_compressed_if_driver.sv: guarded by `if (CVA6Cfg.CvxifEn)`.
#     CvxifEn=COPRO_NONE in our config, so the synthesizer prunes it.
# cva6.sv is listed separately above, so prune it here to avoid a duplicate.
#
# NOTE: cvxif_issue_register_commit_if_driver.sv is UNCONDITIONALLY
# instantiated in issue_read_operands.sv (no `if (CVA6Cfg.CvxifEn)` guard
# in upstream). It must be included even when CvxifEn=0.
CVA6_UPSTREAM_CORE_EXCL := \
    $(CVA6_SUB)/core/cva6.sv \
    $(CVA6_SUB)/core/fpu_wrap.sv \
    $(CVA6_SUB)/core/acc_dispatcher.sv \
    $(CVA6_SUB)/core/cva6_accel_first_pass_decoder_stub.sv \
    $(CVA6_SUB)/core/cvxif_fu.sv \
    $(CVA6_SUB)/core/cvxif_compressed_if_driver.sv
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

# All upstream sources (unique basenames guaranteed when flattened).
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

# Upstream .svh headers (cva6.sv / ariane.sv / hpdcache / instr_tracer
# `include these). They are NOT copied to hardware/src/: the merge script
# inlines them at their `include sites. The script locates them via the
# CVA6_INCLUDE_DIRS override in the cva6 target.
#   $(CVA6_SUB)/core/include/                      cvxif_types.svh, rvfi_types.svh
#   $(CVA6_SUB)/common/local/util/                 ex_trace_item.svh, instr_trace_item.svh
#   $(HPDCACHE_DIR)/rtl/include/                   hpdcache_typedef.svh

# ==============================================================================
# Single-file merge order.
# ==============================================================================
# hardware/src/cva6.sv is built by hardware/cva6_merge.py. Packages MUST be
# emitted before any module that references their types (a module's port /
# parameter list can use `config_pkg::cva6_cfg_t`, `ariane_pkg::*`, etc.),
# and packages must precede the packages they depend on. This is the
# topological order for this configuration:
#
#   config_pkg                     (leaf)
#   axi_pkg                        (leaf)
#   cva6_config_pkg                (IOB; -> config_pkg)
#   riscv_pkg        (pkg `riscv`) (-> cva6_config_pkg)
#   ariane_axi_pkg   (pkg `ariane_axi`) (-> axi_pkg, cva6_config_pkg)
#   ariane_pkg                     (-> config_pkg, cva6_config_pkg)
#   std_cache_pkg                  (-> ariane_pkg)
#   build_config_pkg               (-> config_pkg)
#   cf_math_pkg                    (leaf)
#   wt_cache_pkg                   (leaf)
#   hpdcache_pkg                   (leaf)
#   aes_pkg                        (leaf)
#   triggers_pkg                   (leaf)
#   instr_tracer_pkg               (leaf)
#   dummy_l15_pkg   (pkg `l15_pkg`)(leaf)
#   hwpf_stride_pkg                (leaf)
CVA6_MERGE_PKGS := \
    $(CVA6_SUB)/core/include/config_pkg.sv \
    $(CVA6_SUB)/vendor/pulp-platform/axi/src/axi_pkg.sv \
    $(CVA6_IOB_SV)/cva6_config_pkg.sv \
    $(CVA6_SUB)/core/include/riscv_pkg.sv \
    $(CVA6_SUB)/corev_apu/tb/ariane_axi_pkg.sv \
    $(CVA6_SUB)/core/include/ariane_pkg.sv \
    $(CVA6_SUB)/core/include/std_cache_pkg.sv \
    $(CVA6_SUB)/core/include/build_config_pkg.sv \
    $(CVA6_SUB)/vendor/pulp-platform/common_cells/src/cf_math_pkg.sv \
    $(CVA6_SUB)/core/include/wt_cache_pkg.sv \
    $(HPDCACHE_DIR)/rtl/src/hpdcache_pkg.sv \
    $(CVA6_SUB)/core/include/aes_pkg.sv \
    $(CVA6_SUB)/core/include/triggers_pkg.sv \
    $(CVA6_SUB)/core/include/instr_tracer_pkg.sv \
    $(CVA6_SUB)/core/include/dummy_l15_pkg.sv \
    $(HPDCACHE_DIR)/rtl/src/hwpf_stride/hwpf_stride_pkg.sv

# Everything else is a module. Modules do not need ordering among
# themselves (instantiation is by reference), so we use the upstream
# manifest order and append the IOb top wrapper last. cva6_wrapper.sv is
# the SoC top and references ariane_axi types, so it must come after all
# packages (it does, being a module). hpdcache_pkg / hwpf_stride_pkg which
# appear in CVA6_UPSTREAM_HPD are filtered out (they are packages).
CVA6_MERGE_MODULES := \
    $(filter-out $(CVA6_MERGE_PKGS), $(CVA6_UPSTREAM_SV)) \
    $(CVA6_IOB_SV)/cva6_wrapper.sv

CVA6_MERGE_SCRIPT := $(CVA6_ROOT)/hardware/cva6_merge.py
CVA6_MERGED     := $(CVA6_SRC_DIR)/cva6.sv

.PHONY: cva6
cva6:
	@if [ ! -f "$(CVA6_SUB)/core/cva6.sv" ]; then \
	    echo "ERROR: CVA6 submodule not initialised."; \
	    echo "  Run: git submodule update --init --recursive"; \
	    exit 1; \
	fi
	@if [ -z "$(wildcard $(CVA6_IOB_SV)/*.sv)" ]; then \
	    echo "ERROR: no IObundle-specific sources in $(CVA6_IOB_SV)/."; \
	    echo "  Expected at least cva6_wrapper.sv, cva6_config_pkg.sv."; \
	    exit 1; \
	fi
	@echo "=== Merging SystemVerilog sources into $(CVA6_MERGED) ==="
	@mkdir -p $(CVA6_SRC_DIR)
	@rm -f $(CVA6_SRC_DIR)/*.sv $(CVA6_SRC_DIR)/*.svh $(CVA6_SRC_DIR)/*.v
	@CVA6_INCLUDE_DIRS="$(CVA6_SUB)/core/include:$(CVA6_SUB)/common/local/util:$(HPDCACHE_DIR)/rtl/include" \
	    python3 $(CVA6_MERGE_SCRIPT) $(CVA6_MERGED) \
	    $(CVA6_MERGE_PKGS) $(CVA6_MERGE_MODULES)
	@echo ""
	@echo "Result: $(CVA6_MERGED)"
	@echo "  ($$(grep -c '^package ' $(CVA6_MERGED)) packages, \
$$(grep -c '^module ' $(CVA6_MERGED)) modules, \
$$(wc -l < $(CVA6_MERGED)) lines)"
	@echo ""
	@echo "This is the flat, self-contained CVA6 for the SoC build:"
	@echo "  - Vivado : read_verilog -sv $(CVA6_MERGED)  (+ top cva6_wrapper)"
	@echo "  - Quartus: VERILOG_INPUT_VERSION SYSTEMVERILOG_2005, one file"
	@echo "  - No submodule include paths are required."

.PHONY: clean
clean:
	@echo "Removing generated $(CVA6_MERGED)"
	@rm -f $(CVA6_MERGED)

.PHONY: clean-submodules
clean-submodules:
	git submodule foreach --recursive git clean -ffdx

.PHONY: cva6 clean clean-submodules
# Default target.
.DEFAULT_GOAL := cva6
