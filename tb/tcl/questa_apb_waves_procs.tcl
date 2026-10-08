# =============================================================================
# questa_apb_waves.tcl - QuestaSim waveform plotter for AMBA APB
# =============================================================================
#
#  Adds every signal of an APB interface to the Wave window under a single
# per-interface group (PADDR / PSEL / PENABLE / PWRITE / PWDATA / PRDATA /
# PREADY / PSLVERR). Each signal is colour coded with its own hue:
#
#     PADDR  - blue tones
#     PSEL   - cyan/teal tones
#     PENABLE- green tones
#     PWRITE - orange tones
#     PWDATA - magenta/purple tones
#     PRDATA - red tones
#     PREADY - yellow tones
#     PSLVERR- gray tones
#
# Top-level entry points:
#     apb_wave_add_apb  <hier> <base>
#
#   hier        : module hierarchy path that contains the interface/struct, using
#                 dot separators (e.g. tb  or  tb.dut). Converted to Questa slash
#                 paths internally.
#   base        : interface (or struct) instance name whose members hold the APB
#                 channel signals (e.g. apb_if_inst).
#
# Examples (this testbench):
#   apb_wave_add_apb  tb apb_if_inst
# =============================================================================


# -----------------------------------------------------------------------------
# Colour helper (pure Tcl, simulator agnostic)
# -----------------------------------------------------------------------------

# Format an {r g b} triple (0-255) as a "#rrggbb" colour string.
proc apb_wave_hex {rgb} {
  foreach {r g b} $rgb break
  return [format "#%02x%02x%02x" \
            [expr {int($r) & 0xff}] \
            [expr {int($g) & 0xff}] \
            [expr {int($b) & 0xff}]]
}

# -----------------------------------------------------------------------------
# APB signal map (member name -> base colour)
# -----------------------------------------------------------------------------
# Each entry is a {member {r g b}} pair, ordered request signals first
# (PSEL / PENABLE drive the APB phases) then payload and response signals.
# PADDR   - blue
# PSEL    - cyan/teal
# PENABLE - green
# PWRITE  - orange
# PWDATA  - magenta/purple
# PRDATA  - red
# PREADY  - yellow
# PSLVERR - gray
set ::apb_wave_sigmap {
  {paddr   {40 90 210}}
  {psel    {23 190 207}}
  {penable {44 160 44}}
  {pwrite  {255 127 14}}
  {pwdata  {148 103 189}}
  {prdata  {214 39 40}}
  {pready  {188 189 34}}
  {pslverr {127 127 127}}
}

# -----------------------------------------------------------------------------
# Path derivation
# -----------------------------------------------------------------------------

# Build a Questa hierarchical signal path (leading slash).
# hier uses dot separators (tb or tb.dut) and maps to Questa's slash-separated
# scope path; struct is the interface (or struct) instance holding the APB
# signals. Its members are child signals of that scope, so they are
# selected with a slash: /tb/apb_if_inst/paddr.
proc apb_wave_qpath {hier struct mem} {
  set h [string map {. /} $hier]
  return "/${h}/${struct}/${mem}"
}

# -----------------------------------------------------------------------------
# Waveform builder (Questa-native)
# -----------------------------------------------------------------------------

# Core plotter: given a resolved interface/struct instance name and an APB
# signal map, add each signal to the Wave window under a single group "<prefix>",
# colouring it with its own base hue. sigpfx is an optional string prepended to
# each member name (e.g. "s_apb_") before deriving the signal path; empty means
# none.
proc apb_wave_plot {hier struct sigmap prefix {sigpfx {}}} {
  foreach entry $sigmap {
    foreach {mem rgb} $entry break
    set sig [apb_wave_qpath $hier $struct "${sigpfx}${mem}"]
    set col [apb_wave_hex $rgb]
    if {[catch {add wave -noupdate \
                  -group "$prefix" \
                  -color $col $sig} emsg]} {
      puts "apb_wave: ADDERR $sig :: $emsg"
    }
  }
}

# -----------------------------------------------------------------------------
# Top-level entry points
# -----------------------------------------------------------------------------

# Plot a full APB interface (all signals). sigpfx is an optional prefix
# prepended to every signal name (empty means no prefix).
proc apb_wave_add_apb {hier base group {sigpfx {}}} {
  puts "apb_wave: plotting APB  struct=$base group=$group"
  apb_wave_plot $hier $base $::apb_wave_sigmap $group $sigpfx
}

