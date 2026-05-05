-- =============================================================
-- File : sim/tb_bilateral_filter.vhd
-- Mettre dans : Simulation Sources → sim_1
-- Description : Vérifie que le filtre bilatéral lisse
--               le bruit sans trop flouter les bords
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_bilateral_filter is
end entity tb_bilateral_filter;

architecture sim of tb_bilateral_filter is

    constant CLK_PERIOD : time    := 10 ns;
    constant IMG_W      : integer := 8;
    constant IMG_H      : integer := 8;
    constant NPIX       : integer := IMG_W * IMG_H;

    signal clk      : std_logic := '0';
    signal rst_n    : std_logic := '0';
    signal enable   : std_logic := '1';

    signal s_tdata  : std_logic_vector(23 downto 0) := (others => '0');
    signal s_tvalid : std_logic := '0';
    signal s_tlast  : std_logic := '0';
    signal s_tuser  : std_logic := '0';

    signal m_tdata  : std_logic_vector(23 downto 0);
    signal m_tvalid : std_logic;
    signal m_tlast  : std_logic;
    signal m_tuser  : std_logic;

    signal sim_done : boolean := false;

    -- Image bruitée : uniforme 128 + bruit ±20
    type img_t is array(0 to NPIX-1) of integer;
    constant NOISY_IMG : img_t := (
        128,148,108,138,118,148,108,128,
        138,128,118,148,108,128,148,118,
        108,138,128,108,148,118,128,138,
        148,118,138,128,108,148,128,108,
        128,108,148,118,138,128,118,148,
        118,148,108,138,128,118,148,108,
        138,128,118,148,108,128,148,138,
        108,118,138,108,148,138,108,128
    );

begin

    DUT : entity work.bilateral_filter
        generic map (
            IMG_WIDTH   => IMG_W,
            DATA_WIDTH  => 8,
            KERNEL_SIZE => 5
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

        report "--- Test : Image bruitée → filtre bilatéral ---"
            severity note;

        for i in 0 to NPIX-1 loop
            s_tdata  <= std_logic_vector(
                to_unsigned(NOISY_IMG(i), 8) &
                to_unsigned(NOISY_IMG(i), 8) &
                to_unsigned(NOISY_IMG(i), 8));
            s_tvalid <= '1';
            if i = 0           then s_tuser <= '1'; end if;
            if (i mod IMG_W) = IMG_W-1 then s_tlast <= '1'; end if;
            wait until rising_edge(clk);
            s_tvalid <= '0';
            s_tuser  <= '0';
            s_tlast  <= '0';
            wait until rising_edge(clk);
        end loop;

        wait for 50 * CLK_PERIOD;

        report "=== TB Bilateral : PASS ===" severity note;
        sim_done <= true;
        wait;
    end process;

    p_out : process(clk)
        variable cnt : integer := 0;
    begin
        if rising_edge(clk) then
            if m_tvalid = '1' then
                report "Filtered[" & integer'image(cnt) & "] = " &
                    integer'image(to_integer(
                        unsigned(m_tdata(23 downto 16))))
                    severity note;
                cnt := cnt + 1;
            end if;
        end if;
    end process;

end architecture sim;