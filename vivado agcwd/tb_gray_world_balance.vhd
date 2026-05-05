-- =============================================================
-- File : sim/tb_gray_world_balance.vhd
-- Mettre dans : Simulation Sources → sim_1
-- Description : Vérifie la correction gray-world
--   Image avec forte dominante rouge → gains corrigent
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_gray_world_balance is
end entity tb_gray_world_balance;

architecture sim of tb_gray_world_balance is

    constant CLK_PERIOD : time    := 10 ns;
    constant IMG_W      : integer := 4;
    constant IMG_H      : integer := 4;
    constant NPIX       : integer := IMG_W * IMG_H;

    signal clk        : std_logic := '0';
    signal rst_n      : std_logic := '0';
    signal enable     : std_logic := '1';

    signal s_tdata    : std_logic_vector(23 downto 0) := (others => '0');
    signal s_tvalid   : std_logic := '0';
    signal s_tlast    : std_logic := '0';
    signal s_tuser    : std_logic := '0';

    signal m_tdata    : std_logic_vector(23 downto 0);
    signal m_tvalid   : std_logic;
    signal m_tlast    : std_logic;
    signal m_tuser    : std_logic;

    signal sim_done   : boolean := false;

    -- Image avec dominante rouge : R=200, G=80, B=60
    -- global_mean = (200+80+60)/3 = 113
    -- gain_r = 113/200 = 0.57  → rouge diminue
    -- gain_g = 113/80  = 1.41  → vert augmente
    -- gain_b = 113/60  = 1.88  → bleu augmente
    constant TEST_R : integer := 200;
    constant TEST_G : integer := 80;
    constant TEST_B : integer := 60;

begin

    DUT : entity work.gray_world_balance
        generic map (
            IMG_WIDTH  => IMG_W,
            IMG_HEIGHT => IMG_H,
            DATA_WIDTH => 8
        )
        port map (
            clk        => clk,
            rst_n      => rst_n,
            enable     => enable,
            s_tdata    => s_tdata,
            s_tvalid   => s_tvalid,
            s_tlast    => s_tlast,
            s_tuser    => s_tuser,
            m_tdata    => m_tdata,
            m_tvalid   => m_tvalid,
            m_tlast    => m_tlast,
            m_tuser    => m_tuser
        );

    p_clk : process
    begin
        clk <= '0'; wait for CLK_PERIOD/2;
        clk <= '1'; wait for CLK_PERIOD/2;
        if sim_done then wait; end if;
    end process;

    p_stim : process

        procedure send_pix(
            r, g, b  : in integer;
            is_first  : in boolean;
            is_last   : in boolean
        ) is
        begin
            s_tdata  <= std_logic_vector(
                to_unsigned(r, 8) &
                to_unsigned(g, 8) &
                to_unsigned(b, 8));
            s_tvalid <= '1';
            if is_first then s_tuser <= '1'; end if;
            if is_last  then s_tlast <= '1'; end if;
            wait until rising_edge(clk);
            s_tvalid <= '0';
            s_tuser  <= '0';
            s_tlast  <= '0';
            wait until rising_edge(clk);
        end procedure;

    begin
        rst_n <= '0';
        wait for 4 * CLK_PERIOD;
        rst_n <= '1';
        wait for 2 * CLK_PERIOD;

        -- =====================================================
        -- Passe 1 : Frame pour calcul des gains
        -- (Les gains sont appliqués à la frame suivante)
        -- =====================================================
        report "--- Envoi Frame 1 (calcul gains) ---" severity note;

        for i in 0 to NPIX-1 loop
            send_pix(TEST_R, TEST_G, TEST_B,
                i = 0, i = NPIX-1);
        end loop;

        wait for 10 * CLK_PERIOD;

        -- =====================================================
        -- Passe 2 : Frame corrigée
        -- =====================================================
        report "--- Envoi Frame 2 (correction appliquée) ---"
            severity note;

        for i in 0 to NPIX-1 loop
            send_pix(TEST_R, TEST_G, TEST_B,
                i = 0, i = NPIX-1);
        end loop;

        wait for 20 * CLK_PERIOD;

        -- =====================================================
        -- Test désactivé (enable=0)
        -- =====================================================
        report "--- Test enable=0 ---" severity note;
        enable <= '0';

        for i in 0 to NPIX-1 loop
            send_pix(TEST_R, TEST_G, TEST_B,
                i = 0, i = NPIX-1);
        end loop;

        wait for 20 * CLK_PERIOD;

        report "=== TB GrayWorld : PASS ===" severity note;
        sim_done <= true;
        wait;
    end process;

    -- Collecte et affichage résultats
    p_monitor : process(clk)
    begin
        if rising_edge(clk) then
            if m_tvalid = '1' then
                report "Sortie → R:" &
                    integer'image(to_integer(unsigned(m_tdata(23 downto 16)))) &
                    " G:" &
                    integer'image(to_integer(unsigned(m_tdata(15 downto 8)))) &
                    " B:" &
                    integer'image(to_integer(unsigned(m_tdata(7 downto 0))))
                    severity note;
            end if;
        end if;
    end process;

end architecture sim;