####################################################################
##
##  Core area, power grid, tap cells and pin placement.
##  Sourced by pnr.tcl and fusion.tcl once the design is mapped.
##
##  Author:   Sne Samal
##  Version:  1.0
##  Date:     2026-08-23
##
####################################################################

lab_banner "Floorplan"

# -side_ratio takes proportions: {1 $ASPECT} gives a core whose height
# is ASPECT times its width.
initialize_floorplan \
    -site_def         $SITE_NAME \
    -core_utilization $CORE_UTIL \
    -side_ratio       [list 1 $ASPECT] \
    -core_offset      $CORE_OFFSET

report_utilization

puts ""
puts "  utilization : $CORE_UTIL"
puts "  aspect      : $ASPECT"
puts "  core offset : $CORE_OFFSET um"
puts "  boundary    : [get_attribute [current_block] boundary]"

####################################################################
## Power and ground nets
####################################################################
# The netlist says nothing about power, so the supply nets and every
# cell's connection to them are made here.

if { [sizeof_collection [get_nets -quiet $PWR_NET]] == 0 } {
    create_net -power $PWR_NET
}
if { [sizeof_collection [get_nets -quiet $GND_NET]] == 0 } {
    create_net -ground $GND_NET
}

connect_pg_net -automatic

####################################################################
## Power plan
####################################################################
# Rails: one wire per cell row on M1. Ring: a loop around the core,
# each segment on a layer running its preferred direction.

lab_banner "Power plan"

# How to build the power and ground (pg) rails supplying the std cells
create_pg_std_cell_conn_pattern rail_pattern \
    -rail_width [get_attribute [get_layers M1] default_width] \
    -layers $RAIL_LAYER

# Nothing joins the rails to the ring, so "stop: first_target" runs
# them out to it.
set_pg_strategy rail_strategy -core \
    -pattern { {pattern: rail_pattern} \
               {nets: {$PWR_NET $GND_NET}} } \
    -extension {stop: first_target}

create_pg_ring_pattern ring_pattern \
    -horizontal_layer   $RING_H_LAYER \
    -horizontal_width   $RING_WIDTH \
    -horizontal_spacing $RING_SPACING \
    -vertical_layer     $RING_V_LAYER \
    -vertical_width     $RING_WIDTH \
    -vertical_spacing   $RING_SPACING

# Nets are laid innermost first, so VSS sits beside the core.
# Extending to the die boundary is what generates the block's power pins
set_pg_strategy ring_strategy -core \
    -pattern { {pattern: ring_pattern} \
               {nets: {$GND_NET $PWR_NET}} \
               {offset: {$RING_OFFSET $RING_OFFSET}} } \
    -extension {stop: design_boundary_and_generate_pin}

# Rails are on M1 and the ring on M2 and M3, so every rail-to-ring
# connection is a via.
set_pg_strategy_via_rule pg_via_rule \
    -via_rule { {intersection: adjacent} {via_master: default} }

# Ring first, so the rails have something to stop at.
compile_pg -strategies ring_strategy -via_rule pg_via_rule
compile_pg -strategies rail_strategy -via_rule pg_via_rule

connect_pg_net

####################################################################
## Tap cells
####################################################################

lab_banner "Tap cells"

create_tap_cells \
    -lib_cell [get_lib_cells */$TAP_CELL] \
    -distance $TAP_DISTANCE \
    -pattern  stagger

####################################################################
## Pins
####################################################################

# -self places this block's own pins, not those of any child block.
place_pins -self

# Nothing is placed yet, so only the grid itself is worth checking.
redirect -tee -file $RPT_DIR/floorplan_pg_connectivity.rpt \
    {check_pg_connectivity -check_std_cell_pins none}

save_block -label floorplan
save_lib
