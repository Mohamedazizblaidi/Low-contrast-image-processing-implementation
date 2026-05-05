-- =============================================================
-- File : sim/tb_histogram_engine.vhd
-- Mettre dans : Simulation Sources → sim_1
-- Description : Teste histogram_engine avec des pixels connus
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_histogram_engine is
end entity tb_histogram_engine;

architecture sim of tb_histogram_engine is

    constant CLK_PERIOD : time    := 10 ns;
    constant IMG_W      : integer := 4;
    constant IMG_H      : integer := 4;

    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal pixel_in    : unsigned(7 downto 0) := (others => '0');
    signal pix_valid   : std_logic := '0';
    signal frame_start : std_logic := '0';
    signal frame_end   : std_logic := '0';
    signal rd_addr     : unsigned(7 downto 0) := (others => '0');
    signal rd_data     : unsigned(19 downto 0);
    signal hist_done   : std_logic;

    signal sim_done    : boolean := false;

    -- Image connue : 4 pixels=10, 4 pixels=50,
    --                4 pixels=100, 4 pixels=200
    type pixel_seq_t is array(0 to 15) of integer;
    constant PIXELS : pixel_seq_t := (
        10, 10, 10, 10,
        50, 50, 50, 50,
       100,100,100,100,
       200,200,200,200
    );

begin

    DUT : entity work.histogram_engine
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
            rd_addr     => rd_addr,
            rd_data     => rd_data,
            hist_done   => hist_done
        );

    -- Horloge
    p_clk : process
    begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
        if sim_done then wait; end if;
    end process;

    -- Stimulus
    p_stim : process
    begin
        -- Reset
        rst_n <= '0';
        wait for 4 * CLK_PERIOD;
        rst_n <= '1';
        wait for 2 * CLK_PERIOD;

        -- Envoyer les 16 pixels
        frame_start <= '1';
        wait until rising_edge(clk);
        frame_start <= '0';

        for i in 0 to 15 loop
            pixel_in  <= to_unsigned(PIXELS(i), 8);
            pix_valid <= '1';
            if i = 15 then frame_end <= '1'; end if;
            wait until rising_edge(clk);
            pix_valid  <= '0';
            frame_end  <= '0';
            wait until rising_edge(clk);
        end loop;

        -- Attendre hist_done
        wait until hist_done = '1';
        wait for 2 * CLK_PERIOD;

        -- =====================================================
        -- Vérifications
        -- =====================================================
        -- bin[10] doit valoir 4
        rd_addr <= to_unsigned(10, 8);
        wait for 2 * CLK_PERIOD;
        assert rd_data = 4
            report "ERREUR bin[10] = " &
                integer'image(to_integer(rd_data)) &
                " attendu 4"
            severity error;
        report "bin[10] = " &
            integer'image(to_integer(rd_data))
            severity note;

        -- bin[50] doit valoir 4
        rd_addr <= to_unsigned(50, 8);
        wait for 2 * CLK_PERIOD;
        assert rd_data = 4
            report "ERREUR bin[50] = " &
                integer'image(to_integer(rd_data)) &
                " attendu 4"
            severity error;
        report "bin[50] = " &
            integer'image(to_integer(rd_data))
            severity note;

        -- bin[100] doit valoir 4
        rd_addr <= to_unsigned(100, 8);
        wait for 2 * CLK_PERIOD;
        assert rd_data = 4
            report "ERREUR bin[100] = " &
                integer'image(to_integer(rd_data)) &
                " attendu 4"
            severity error;
        report "bin[100] = " &
            integer'image(to_integer(rd_data))
            severity note;

        -- bin[200] doit valoir 4
        rd_addr <= to_unsigned(200, 8);
        wait for 2 * CLK_PERIOD;
        assert rd_data = 4
            report "ERREUR bin[200] = " &
                integer'image(to_integer(rd_data)) &
                " attendu 4"
            severity error;
        report "bin[200] = " &
            integer'image(to_integer(rd_data))
            severity note;

        -- bin[0] doit valoir 0
        rd_addr <= to_unsigned(0, 8);
        wait for 2 * CLK_PERIOD;
        assert rd_data = 0
            report "ERREUR bin[0] = " &
                integer'image(to_integer(rd_data)) &
                " attendu 0"
            severity error;

        report "=== TB Histogram : PASS ===" severity note;
        sim_done <= true;
        wait;
    end process;

end architecture sim;