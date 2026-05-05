-- =============================================================
-- File : sim/tb_channel_stats.vhd
-- Mettre dans : Simulation Sources → sim_1
-- Description : Vérifie le calcul mean/std et la classification
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_channel_stats is
end entity tb_channel_stats;

architecture sim of tb_channel_stats is

    constant CLK_PERIOD : time    := 10 ns;
    constant IMG_W      : integer := 4;
    constant IMG_H      : integer := 4;

    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal pixel_in    : std_logic_vector(23 downto 0) := (others => '0');
    signal pix_valid   : std_logic := '0';
    signal frame_start : std_logic := '0';
    signal frame_end   : std_logic := '0';
    signal mean_out    : unsigned(7 downto 0);
    signal std_out     : unsigned(7 downto 0);
    signal is_dark     : std_logic;
    signal is_bright   : std_logic;
    signal stats_done  : std_logic;

    signal sim_done    : boolean := false;

    -- Procédure pour envoyer une frame uniforme
    procedure send_uniform_frame(
        signal clk         : in  std_logic;
        signal pixel_in    : out std_logic_vector(23 downto 0);
        signal pix_valid   : out std_logic;
        signal frame_start : out std_logic;
        signal frame_end   : out std_logic;
        constant r_val     : in  integer;
        constant g_val     : in  integer;
        constant b_val     : in  integer;
        constant npix      : in  integer
    ) is
    begin
        frame_start <= '1';
        pixel_in    <= std_logic_vector(
            to_unsigned(r_val, 8) &
            to_unsigned(g_val, 8) &
            to_unsigned(b_val, 8));
        pix_valid <= '1';
        wait until rising_edge(clk);
        frame_start <= '0';

        for i in 1 to npix-1 loop
            if i = npix-1 then frame_end <= '1'; end if;
            wait until rising_edge(clk);
        end loop;

        pix_valid  <= '0';
        frame_end  <= '0';
        wait until rising_edge(clk);
    end procedure;

begin

    DUT : entity work.channel_stats
        generic map (
            IMG_WIDTH  => IMG_W,
            IMG_HEIGHT => IMG_H,
            DATA_WIDTH => 8
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            pixel_in    => pixel_in,
            pix_valid   => pix_valid,
            frame_start => frame_start,
            frame_end   => frame_end,
            mean_out    => mean_out,
            std_out     => std_out,
            is_dark     => is_dark,
            is_bright   => is_bright,
            stats_done  => stats_done
        );

    p_clk : process
    begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
        if sim_done then wait; end if;
    end process;

    p_stim : process
    begin
        rst_n <= '0';
        wait for 4 * CLK_PERIOD;
        rst_n <= '1';
        wait for 2 * CLK_PERIOD;

        -- =====================================================
        -- Test 1 : Image très sombre (R=3,G=3,B=3)
        -- Attendu : is_dark='1'
        -- =====================================================
        report "--- Test 1 : Image sombre ---" severity note;
        send_uniform_frame(clk, pixel_in, pix_valid,
            frame_start, frame_end,
            3, 3, 3, IMG_W*IMG_H);

        wait until stats_done = '1';
        wait for 2 * CLK_PERIOD;

        report "Mean = " & integer'image(to_integer(mean_out))
            severity note;
        report "Std  = " & integer'image(to_integer(std_out))
            severity note;

        assert is_dark = '1'
            report "ERREUR : is_dark devrait être 1" severity error;
        assert is_bright = '0'
            report "ERREUR : is_bright devrait être 0" severity error;

        report "Test 1 : PASS" severity note;
        wait for 5 * CLK_PERIOD;

        -- =====================================================
        -- Test 2 : Image très claire (R=252,G=252,B=252)
        -- Attendu : is_bright='1'
        -- =====================================================
        report "--- Test 2 : Image claire ---" severity note;
        send_uniform_frame(clk, pixel_in, pix_valid,
            frame_start, frame_end,
            252, 252, 252, IMG_W*IMG_H);

        wait until stats_done = '1';
        wait for 2 * CLK_PERIOD;

        report "Mean = " & integer'image(to_integer(mean_out))
            severity note;

        assert is_bright = '1'
            report "ERREUR : is_bright devrait être 1" severity error;
        assert is_dark = '0'
            report "ERREUR : is_dark devrait être 0" severity error;

        report "Test 2 : PASS" severity note;
        wait for 5 * CLK_PERIOD;

        -- =====================================================
        -- Test 3 : Image normale (R=100,G=120,B=80)
        -- Attendu : is_dark=0, is_bright=0
        -- =====================================================
        report "--- Test 3 : Image normale ---" severity note;
        send_uniform_frame(clk, pixel_in, pix_valid,
            frame_start, frame_end,
            100, 120, 80, IMG_W*IMG_H);

        wait until stats_done = '1';
        wait for 2 * CLK_PERIOD;

        report "Mean = " & integer'image(to_integer(mean_out))
            severity note;

        assert is_dark = '0'
            report "ERREUR : is_dark devrait être 0" severity error;
        assert is_bright = '0'
            report "ERREUR : is_bright devrait être 0" severity error;

        report "Test 3 : PASS" severity note;

        report "=== TB channel_stats : PASS ===" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture sim;