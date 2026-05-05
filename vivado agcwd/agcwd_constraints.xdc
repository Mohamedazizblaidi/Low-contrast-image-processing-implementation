# =============================================================
# File: agcwd_constraints.xdc
# Target: Xilinx Artix-7 XC7A35T (Basys3) ou Zynq-7000 ZC702
# =============================================================

# -------------------------------------------------------------
# Horloge principale : 100 MHz
# -------------------------------------------------------------
create_clock -period 10.000 -name clk_100mhz \
    [get_ports clk]

# -------------------------------------------------------------
# Contraintes I/O (exemple pour HDMI / PMOD)
# -------------------------------------------------------------

# Entrée pixel R[7:0]
set_input_delay -clock clk_100mhz -max 3.0 \
    [get_ports {s_axis_tdata[*]}]
set_input_delay -clock clk_100mhz -min 0.5 \
    [get_ports {s_axis_tdata[*]}]

set_input_delay -clock clk_100mhz -max 3.0 \
    [get_ports {s_axis_tvalid s_axis_tlast s_axis_tuser}]
set_input_delay -clock clk_100mhz -min 0.5 \
    [get_ports {s_axis_tvalid s_axis_tlast s_axis_tuser}]

# Sortie pixel
set_output_delay -clock clk_100mhz -max 3.0 \
    [get_ports {m_axis_tdata[*]}]
set_output_delay -clock clk_100mhz -min 0.5 \
    [get_ports {m_axis_tdata[*]}]

set_output_delay -clock clk_100mhz -max 3.0 \
    [get_ports {m_axis_tvalid m_axis_tlast m_axis_tuser}]
set_output_delay -clock clk_100mhz -min 0.5 \
    [get_ports {m_axis_tvalid m_axis_tlast m_axis_tuser}]

# Signaux de contrôle
set_input_delay -clock clk_100mhz -max 5.0 \
    [get_ports {enable_denoise enable_sharpen enable_balance}]

# Reset asynchrone
set_false_path -from [get_ports rst_n]

# -------------------------------------------------------------
# Placement des BRAMs histogramme
# (optionnel selon la taille du FPGA)
# -------------------------------------------------------------
# set_property LOC RAMB36_X0Y0 [get_cells u_hist_r/hist_ram_reg]
# set_property LOC RAMB36_X0Y1 [get_cells u_hist_g/hist_ram_reg]
# set_property LOC RAMB36_X0Y2 [get_cells u_hist_b/hist_ram_reg]

# -------------------------------------------------------------
# Configuration FPGA
# -------------------------------------------------------------
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

# Bitstream
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

# -------------------------------------------------------------
# Pfalse paths pour les LUTs gamma (RAM statiques en lecture)
# -------------------------------------------------------------
set_false_path -through [get_nets {lut_r_out[*] lut_g_out[*] lut_b_out[*]}]