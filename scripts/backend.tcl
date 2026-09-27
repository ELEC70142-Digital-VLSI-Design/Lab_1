####################################################################
##
##  Clock tree, routing, chip finish and export. Identical for both
##  flows, which is what makes their results comparable.
##
##  Author:   Sne Samal
##  Version:  1.0
##  Date:     2026-08-23
##
####################################################################

####################################################################
## Clock tree synthesis
####################################################################

lab_banner "Clock tree synthesis"

# Clock buffers and inverters only. Exclude everything, then add them back.
set cts_cells {}
foreach c [concat $CTS_BUFFERS $CTS_INVERTERS] { lappend cts_cells */$c }
set cts_cells [get_lib_cells $cts_cells]

puts "  clock tree cells: [sizeof_collection $cts_cells]"

# ATTR-12 fires once per library cell otherwise.
suppress_message ATTR-12
set_lib_cell_purpose -exclude cts [get_lib_cells]
set_lib_cell_purpose -include cts $cts_cells
unsuppress_message ATTR-12

set_clock_tree_options -target_skew 0.2 -clocks [get_clocks $CLK_PORT]
set_max_transition 0.13 -clock_path [get_clocks $CLK_PORT]

# Cells driven by one clock buffer. Caps the load on any tree stage.
set_app_options -name cts.common.max_fanout -value 20

# Tells clock tree synthesis clocks transition time - matches max transition time
set_app_options -name cts.common.default_max_transition -value 0.13

# build_clock, route_clock, then final_opto against the real clock.
clock_opt

catch {redirect -file $RPT_DIR/cts_clock_qor.rpt  {report_clock_qor}}
catch {redirect -file $RPT_DIR/cts_clock_skew.rpt {report_clock_timing -type skew}}

lab_reports cts
lab_headline
save_block -label cts
save_lib

####################################################################
## Routing
####################################################################

lab_banner "Routing"

# Route the design
route_auto

# Optimise routes
hyper_route_opt

# Check connectivity + DRCs
check_routes

lab_reports route
lab_headline
save_block -label route
save_lib

####################################################################
## Chip finish
####################################################################
# Fillers carry the wells, implants and power rails across the gaps
# between cells. Largest first, which the tool requires.

lab_banner "Chip finish"

set fillers {}
foreach c $FILLER_CELLS { lappend fillers */$c }

create_stdcell_fillers -lib_cells [get_lib_cells $fillers]

# Anything that inserts cells has to reconnect power afterwards.
connect_pg_net -automatic

# Check violations due to filler cells
remove_stdcell_fillers_with_violation

# Saved before the checks, so a failure still leaves a block to open.
save_block -label finish
save_lib

####################################################################
## Checks
####################################################################
# The tool checking its own work, not signoff. These report violations
# and still return success, so the flow does not stop on them.

lab_banner "Checks"

redirect -tee -file $RPT_DIR/finish_legality.rpt        {check_legality}
redirect -tee -file $RPT_DIR/finish_routes.rpt          {check_routes}
redirect -tee -file $RPT_DIR/finish_pg_drc.rpt          {check_pg_drc}
redirect -tee -file $RPT_DIR/finish_pg_connectivity.rpt {check_pg_connectivity}
redirect -tee -file $RPT_DIR/finish_lvs.rpt             {check_lvs -max_errors 0}

# Extraction happens as part of the timing update.
update_timing

lab_reports finish
lab_headline

####################################################################
## Export
####################################################################

lab_banner "Export"

# Make every instance and net name legal Verilog before anything is
# written, so the netlist, SDF and SPEF agree on what things are
# called. Without it bus bits reach the SDF as escaped identifiers
# and VCS cannot match them to the netlist.
change_names -rules verilog -hierarchy

# Filler and tap cells have no Verilog models and the vendor models
# declare no power ports, so both are left out or VCS will not
# elaborate. The design library and the DEF still hold every one.
write_verilog -exclude {all_physical_cells pg_netlist} $LAYOUT_V

write_def $OUT_DIR/${DESIGN}.def
write_lef $OUT_DIR/${DESIGN}.lef
write_sdc -output $OUT_DIR/${DESIGN}_final.sdc
write_sdf -corner $SDF_CORNER $OUT_DIR/${DESIGN}_${SDF_CORNER}.sdf

write_parasitics -corner $SDF_CORNER -output $OUT_DIR/${DESIGN}

save_block -label finish
save_lib

puts ""
puts "  Files in $OUT_DIR:"
foreach f [lsort [glob -nocomplain $OUT_DIR/*]] {
    puts [format "    %-44s %d bytes" $f [file size $f]]
}

lab_banner "Layout complete"

puts "  Every check wrote a report. Read the summary at the end of each:"
puts ""
puts "    $RPT_DIR/finish_legality.rpt         every cell in a legal site"
puts "    $RPT_DIR/finish_routes.rpt           every net routed, no rule broken"
puts "    $RPT_DIR/finish_pg_drc.rpt           power grid spacing and width"
puts "    $RPT_DIR/finish_pg_connectivity.rpt  power reaches every cell"
puts "    $RPT_DIR/finish_lvs.rpt              shorts, opens, floating routes"
puts ""
puts "  A clean run says, in finish_routes.rpt:"
puts "      Total number of open nets = 0"
puts "      Total number of DRCs = 0"
puts ""
puts "  Timing and area are in $RPT_DIR/finish_*.rpt."
puts ""
puts "  View it:  start_gui"
puts "  Simulate: make sim-layout FLOW=$FLOW"
