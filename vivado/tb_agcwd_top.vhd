-- =============================================================
-- File: tb_agcwd_hex.vhd
-- Testbench for AGCWD using hex pixel files
-- Input format: one 24-bit RGB pixel per line as RRGGBB
-- Compatible with Vivado 2018.2
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_agcwd_hex is
end entity tb_agcwd_hex;

architecture sim of tb_agcwd_hex is

    -- =========================================================
    -- Clock
    -- =========================================================
    constant CLK_PERIOD : time := 10 ns;

    -- =========================================================
    -- Image size
    -- =========================================================
    constant IMG_W : integer := 960;
    constant IMG_H : integer := 640;

    -- =========================================================
    -- File paths
    -- =========================================================
    constant INPUT_FILE  : string :=
        "C:/Users/ACER/Downloads/Electronics project/input_image.hex";

    constant OUTPUT_FILE : string :=
        "C:/Users/ACER/Downloads/Electronics project/output_image.hex";

    -- =========================================================
    -- DUT signals
    -- =========================================================
    signal clk             : std_logic := '0';
    signal rst_n           : std_logic := '0';

    signal s_axis_tdata    : std_logic_vector(23 downto 0) := (others => '0');
    signal s_axis_tvalid   : std_logic := '0';
    signal s_axis_tready   : std_logic;
    signal s_axis_tlast    : std_logic := '0';
    signal s_axis_tuser    : std_logic := '0';

    signal m_axis_tdata    : std_logic_vector(23 downto 0);
    signal m_axis_tvalid   : std_logic;
    signal m_axis_tready   : std_logic := '1';
    signal m_axis_tlast    : std_logic;
    signal m_axis_tuser    : std_logic;

    -- =========================================================
    -- Controls
    -- =========================================================
    signal enable_denoise  : std_logic := '0';
    signal enable_sharpen  : std_logic := '0';
    signal enable_balance  : std_logic := '0';

    signal frame_done      : std_logic;
    signal frame_dark      : std_logic;
    signal frame_bright    : std_logic;

    -- =========================================================
    -- Files
    -- =========================================================
    file fin  : text open read_mode  is INPUT_FILE;
    file fout : text open write_mode is OUTPUT_FILE;

    -- =========================================================
    -- Helper function: convert 24-bit std_logic_vector to hex string
    -- =========================================================
    function slv24_to_hex(s : std_logic_vector(23 downto 0)) return string is
        variable result : string(1 to 6);
        variable nibble : std_logic_vector(3 downto 0);
    begin
        for i in 0 to 5 loop
            nibble := s(23 - i*4 downto 20 - i*4);
            case nibble is
                when "0000" => result(i+1) := '0';
                when "0001" => result(i+1) := '1';
                when "0010" => result(i+1) := '2';
                when "0011" => result(i+1) := '3';
                when "0100" => result(i+1) := '4';
                when "0101" => result(i+1) := '5';
                when "0110" => result(i+1) := '6';
                when "0111" => result(i+1) := '7';
                when "1000" => result(i+1) := '8';
                when "1001" => result(i+1) := '9';
                when "1010" => result(i+1) := 'A';
                when "1011" => result(i+1) := 'B';
                when "1100" => result(i+1) := 'C';
                when "1101" => result(i+1) := 'D';
                when "1110" => result(i+1) := 'E';
                when others  => result(i+1) := 'F';
            end case;
        end loop;
        return result;
    end function;

begin

    -- =========================================================
    -- DUT
    -- =========================================================
    DUT : entity work.agcwd_top
        generic map (
            IMG_WIDTH   => IMG_W,
            IMG_HEIGHT  => IMG_H,
            ALPHA_VALUE => 128
        )
        port map (
            clk             => clk,
            rst_n           => rst_n,
            s_axis_tdata    => s_axis_tdata,
            s_axis_tvalid   => s_axis_tvalid,
            s_axis_tready   => s_axis_tready,
            s_axis_tlast    => s_axis_tlast,
            s_axis_tuser    => s_axis_tuser,
            m_axis_tdata    => m_axis_tdata,
            m_axis_tvalid   => m_axis_tvalid,
            m_axis_tready   => m_axis_tready,
            m_axis_tlast    => m_axis_tlast,
            m_axis_tuser    => m_axis_tuser,
            enable_denoise  => enable_denoise,
            enable_sharpen  => enable_sharpen,
            enable_balance  => enable_balance,
            frame_done      => frame_done,
            frame_dark      => frame_dark,
            frame_bright    => frame_bright
        );

    -- =========================================================
    -- Clock generation
    -- =========================================================
    p_clk : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
    end process p_clk;

    -- =========================================================
    -- Stimulus: read input file and send pixels
    -- =========================================================
    p_stim : process
        variable L       : line;
        variable pix_hex : std_logic_vector(23 downto 0);
        variable pix_id  : integer := 0;
    begin
        -- Reset
        rst_n <= '0';
        wait for 5 * CLK_PERIOD;
        rst_n <= '1';
        wait for 5 * CLK_PERIOD;

        report "Reading input_image.hex..." severity note;

        while not endfile(fin) loop
            readline(fin, L);
            hread(L, pix_hex);

            -- tuser = '1' only for the first pixel of the frame
            if pix_id = 0 then
                s_axis_tuser <= '1';
            else
                s_axis_tuser <= '0';
            end if;

            -- tlast = '1' only on the last pixel of each line
            if (pix_id mod IMG_W) = IMG_W - 1 then
                s_axis_tlast <= '1';
            else
                s_axis_tlast <= '0';
            end if;

            s_axis_tdata  <= pix_hex;
            s_axis_tvalid <= '1';

            -- Wait for handshake: DUT accepts pixel on rising edge
            -- when both tvalid and tready are high
            wait until rising_edge(clk) and s_axis_tready = '1';

            pix_id := pix_id + 1;
        end loop;

        -- De-assert after all pixels are sent
        s_axis_tvalid <= '0';
        s_axis_tuser  <= '0';
        s_axis_tlast  <= '0';

        report "All input pixels sent." severity note;

        -- Give time for output pipeline
        wait for 20 ms;

        report "End of simulation." severity note;
        wait;
    end process p_stim;

    -- =========================================================
    -- Capture output into output_image.hex
    -- =========================================================
    p_capture : process(clk)
        variable Lout      : line;
        variable out_count : integer := 0;
    begin
        if rising_edge(clk) then
            if m_axis_tvalid = '1' then
                hwrite(Lout, m_axis_tdata);
                writeline(fout, Lout);

                out_count := out_count + 1;

                report "OUT[" & integer'image(out_count) & "] = " &
                       slv24_to_hex(m_axis_tdata)
                       severity note;
            end if;
        end if;
    end process p_capture;

    -- =========================================================
    -- Optional checks
    -- =========================================================
    p_check : process(clk)
    begin
        if rising_edge(clk) then
            if m_axis_tvalid = '1' then
                assert to_integer(unsigned(m_axis_tdata(23 downto 16))) <= 255
                    report "ERROR: R out of range" severity error;
                assert to_integer(unsigned(m_axis_tdata(15 downto 8))) <= 255
                    report "ERROR: G out of range" severity error;
                assert to_integer(unsigned(m_axis_tdata(7 downto 0))) <= 255
                    report "ERROR: B out of range" severity error;
            end if;

            assert not (frame_dark = '1' and frame_bright = '1')
                report "ERROR: frame_dark and frame_bright both high"
                severity error;
        end if;
    end process p_check;

end architecture sim;