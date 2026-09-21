####################################################################
##
##  Kit, design parameters, directories and reporting helpers.
##  Sourced first by every flow script, which sets FLOW beforehand.
##
##  Author:   Sne Samal
##  Version:  1.0
##  Date:     2026-08-23
##
####################################################################

if { ![info exists FLOW] } {
    error "Set FLOW to logical or fusion before sourcing setup.tcl"
}

if { ![info exists env(SYN_KIT_TCL)] } {
    error "SYN_KIT_TCL is not set. Run 'tools/syn tsmc65LP' from the repo root first."
}

source $env(SYN_KIT_TCL)

# Fail here rather than several stages later if the kit is out of date.
foreach v {
    TECH_FILE REF_LIBS SIM_MODELS
    TLUPLUS_MAX TLUPLUS_MIN TLUPLUS_TYP
    CORNER_LABELS CORNER_VOLTAGE CORNER_TEMP
    SITE_NAME SITE_SYMMETRY
    HORIZONTAL_LAYERS VERTICAL_LAYERS
    RAIL_LAYER RING_H_LAYER RING_V_LAYER
    TAP_CELL TAP_DISTANCE TIE_HI_CELL TIE_LO_CELL DRIVE_CELL
    FILLER_CELLS CTS_BUFFERS CTS_INVERTERS
    PWR_NET GND_NET
} {
    if { ![info exists $v] && ![array exists $v] } {
        error "Kit $env(SYN_KIT_TCL) does not define $v. Copy tools/ across again."
    }
}

####################################################################
## Design
####################################################################

set DESIGN   lfsr4
set CLK_PORT clk

set RTL_FILES src/$DESIGN.sv
set SDC_FILE  constraints/$DESIGN.sdc

####################################################################
## Settings you may want to change
####################################################################
# The clock is not here. It lives in the SDC file.

set CORE_UTIL   0.6         ;# fraction of the core available to cells
set ASPECT      1.0         ;# core height / width
set CORE_OFFSET 5           ;# core to die edge, um

set RING_WIDTH   1.0        ;# power ring, um
set RING_SPACING 0.5
# Centres the ring set in the core-to-die channel:
# (CORE_OFFSET - (2 * RING_WIDTH + RING_SPACING)) / 2.
set RING_OFFSET  1.25

# On-chip variation, applied at every corner in scripts/mcmm.tcl.
set DERATE_EARLY 0.95
set DERATE_LATE  1.05

set SDF_CORNER  tc          ;# corner the simulation SDF is written at
set MAX_CORES   8

# func_wc has dynamic power disabled, so power is reported from tc.
set POWER_SCENARIO func_tc

####################################################################
## Directories and files
####################################################################

set WORK_DIR work
set OUT_DIR  outputs/$FLOW
set RPT_DIR  reports/$FLOW

foreach d [list $WORK_DIR $OUT_DIR $RPT_DIR] { file mkdir $d }

# A non-physical block cannot become a physical one, so the logical
# flow needs two libraries with the netlist as the handoff. The fusion
# flow uses PNR_LIB throughout.
set SYN_LIB $WORK_DIR/${DESIGN}_syn.dlib
set PNR_LIB $WORK_DIR/${DESIGN}_${FLOW}.dlib

set SYNTH_V   $OUT_DIR/${DESIGN}_synth.v
set SYNTH_SDC $OUT_DIR/${DESIGN}_synth.sdc
set LAYOUT_V  $OUT_DIR/${DESIGN}_layout.v

####################################################################
## Helpers
####################################################################
# Prefixed lab_ because the tool refuses to create a procedure whose
# name collides with one of its own commands.

proc lab_banner {text} {
    puts ""
    puts "=================================================================="
    puts "  $text"
    puts "=================================================================="
}

# One call per stage, so a stage's effect is a diff against the one
# before it.
proc lab_reports {stage {physical 1}} {
    global RPT_DIR POWER_SCENARIO

    redirect -file $RPT_DIR/${stage}_timing_max.rpt \
        {report_timing -delay_type max -max_paths 10}
    redirect -file $RPT_DIR/${stage}_timing_min.rpt \
        {report_timing -delay_type min -max_paths 10}
    redirect -file $RPT_DIR/${stage}_area.rpt  {report_area}
    redirect -file $RPT_DIR/${stage}_qor.rpt   {report_qor}
    redirect -file $RPT_DIR/${stage}_power.rpt \
        "report_power -scenarios $POWER_SCENARIO"

    if { $physical } {
        catch {redirect -file $RPT_DIR/${stage}_utilization.rpt {report_utilization}}
        catch {redirect -file $RPT_DIR/${stage}_congestion.rpt  {report_congestion}}
    }

    puts "Reports written to $RPT_DIR/${stage}_*.rpt"
}

proc lab_headline {} {
    global DESIGN

    set area  "n/a"
    set slack "n/a"
    set cells "n/a"

    catch { set area [get_attribute [get_designs $DESIGN] cell_area] }
    catch {
        set path [get_timing_paths -delay_type max -max_paths 1]
        if { [sizeof_collection $path] > 0 } {
            set slack [get_attribute $path slack]
        }
    }
    catch { set cells [sizeof_collection [get_cells -quiet -hierarchical]] }

    puts ""
    puts "  cell area        : $area um2"
    puts "  worst setup slack: $slack ns"
    puts "  leaf cells       : $cells"
}
