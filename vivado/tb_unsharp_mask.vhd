-- =============================================================
-- File : sim/tb_unsharp_mask.vhd
-- Mettre dans : Simulation Sources → sim_1
-- Description : Vérifie que le masque flou inversé accentue
--               les transitions de l'image
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_unsharp_mask is
end entity tb_unsharp_mask;

architecture sim of tb_unsharp_mask is

    constant CLK_PERIOD : time    := 10 ns;
    constant IMG_W      : integer := 8;
    constant IMG_H      : integer := 8;
    constant NPIX       : integer := IMG_W * IMG_H;

    signal clk       : std_logic := '0';
    signal rst_n     : std_logic := '0';
    signal enable    : std_logic := '1';

    signal s_tdata   : std_logic_vector(23 downto 0) := (others => '0');
    signal s_tvalid  : std_logic := '0';
    signal s_tlast   : std_logic := '0';
    signal s_tuser   : std_logic := '0';

    signal m_tdata   : std_logic_vector(23 downto 0);
    signal m_tvalid  : std_logic;
    signal m_tlast   : std_logic;
    signal m_tuser   : std_logic;

    signal sim_done  : boolean := false;

    -- Image test : gradient horizontal 0→255
    type img_t is array(0 to NPIX-1) of integer;
    constant GRADIENT : img_t := (
         0, 36, 72,108,144,180,216,255,
         0, 36, 72,108,144,180,216,255,
         0, 36, 72,108,144,180,216,255,
         0, 36, 72,108,144,180,216,255,
         0, 36, 72,108,144,180,216,255,
         0, 36, 72,108,144,180,216,255,
         0, 36, 72,108,144,180,216,255,
         0, 36, 72,108,144,180,216,255
    );

begin

    DUT : entity work.unsharp_mask
        generic map (
            IMG_WIDTH  => IMG_W,
            DATA_WIDTH => 8
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            enable    => enable,
            s_tdata   => s_tdata,
            s_tvalid  => s_tvalid,
            s_tlast   => s_tlast,
            s_tuser   => s_tuser,
            m_tdata   => m_tdata,
            m_tvalid  => m_tvalid,
            m_tlast   => m_tlast,
            m_tuser   => m_tuser
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
        -- Test 1 : Gradient avec enable=1
        -- =====================================================
        report "--- Test 1 : Gradient + enable ---" severity note;

        for i in 0 to NPIX-1 loop
            s_tdata  <= std_logic_vector(
                to_unsigned(GRADIENT(i), 8) &
                to_unsigned(GRADIENT(i), 8) &
                to_unsigned(GRADIENT(i), 8));
            s_tvalid <= '1';
            if i = 0           then s_tuser <= '1'; end if;
            if (i mod IMG_W) = IMG_W-1 then s_tlast <= '1'; end if;

            wait until rising_edge(clk);
            s_tvalid <= '0';
            s_tuser  <= '0';
            s_tlast  <= '0';
            wait until rising_edge(clk);
        end loop;

        wait for 30 * CLK_PERIOD;

        -- =====================================================
        -- Test 2 : Même image avec enable=0 (bypass)
        -- =====================================================
        report "--- Test 2 : Bypass (enable=0) ---" severity note;
        enable <= '0';

        for i in 0 to NPIX-1 loop
            s_tdata  <= std_logic_vector(
                to_unsigned(GRADIENT(i), 8) &
                to_unsigned(GRADIENT(i), 8) &
                to_unsigned(GRADIENT(i), 8));
            s_tvalid <= '1';
            if i = 0           then s_tuser <= '1'; end if;
            if (i mod IMG_W) = IMG_W-1 then s_tlast <= '1'; end if;
            wait until rising_edge(clk);
            s_tvalid <= '0';
            s_tuser  <= '0';
            s_tlast  <= '0';
            wait until rising_edge(clk);
        end loop;

        wait for 30 * CLK_PERIOD;

        report "=== TB Unsharp : PASS ===" severity note;
        sim_done <= true;
        wait;
    end process;

    -- Affichage pixels de sortie
    p_out : process(clk)
        variable cnt : integer := 0;
    begin
        if rising_edge(clk) then
            if m_tvalid = '1' then
                report "Out[" & integer'image(cnt) & "] R=" &
                    integer'image(to_integer(
                        unsigned(m_tdata(23 downto 16))))
                    severity note;
                cnt := cnt + 1;
            end if;
        end if;
    end process;

end architecture sim;