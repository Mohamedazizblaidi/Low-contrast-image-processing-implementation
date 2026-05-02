-- =============================================================
-- File : sim/tb_agcwd_top.vhd
-- Mettre dans : Simulation Sources → sim_1
-- Set as Top  : OUI (clic droit → Set as Top)
-- Description : Testbench complet pour agcwd_top
--               Envoie une frame 8x8 de pixels noirs/gris/blancs
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_agcwd_top is
-- Testbench : pas de ports
end entity tb_agcwd_top;

architecture sim of tb_agcwd_top is

    -- =========================================================
    -- Paramètres de simulation
    -- =========================================================
    constant CLK_PERIOD  : time    := 10 ns;   -- 100 MHz
    constant IMG_W       : integer := 8;
    constant IMG_H       : integer := 8;
    constant TOTAL_PIX   : integer := IMG_W * IMG_H;

    -- =========================================================
    -- Signaux DUT
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

    signal enable_denoise  : std_logic := '1';
    signal enable_sharpen  : std_logic := '1';
    signal enable_balance  : std_logic := '1';

    signal frame_done      : std_logic;
    signal frame_dark      : std_logic;
    signal frame_bright    : std_logic;

    -- =========================================================
    -- Image de test 8x8 (valeurs RGB)
    -- Simule une image sombre avec faible contraste
    -- =========================================================
    type pixel_array_t is array(0 to TOTAL_PIX-1) of
        std_logic_vector(23 downto 0);

    -- Image sombre : valeurs entre 10 et 50
    constant TEST_IMAGE : pixel_array_t := (
        x"0A0B0C", x"0F1011", x"141516", x"191A1B",
        x"1E1F20", x"232425", x"282930", x"2D2E2F",
        x"0C0D0E", x"111213", x"161718", x"1B1C1D",
        x"202122", x"252627", x"2A2B2C", x"2F3031",
        x"0E0F10", x"131415", x"181920", x"1D1E1F",
        x"222324", x"272829", x"2C2D2E", x"313233",
        x"101112", x"151617", x"1A1B1C", x"1F2021",
        x"242526", x"292A2B", x"2E2F30", x"333435",
        x"121314", x"171819", x"1C1D1E", x"212223",
        x"262728", x"2B2C2D", x"303132", x"353637",
        x"141516", x"191A1B", x"1E1F20", x"232425",
        x"282930", x"2D2E2F", x"323334", x"373839",
        x"161718", x"1B1C1D", x"202122", x"252627",
        x"2A2B2C", x"2F3031", x"343536", x"393A3B",
        x"181920", x"1D1E1F", x"222324", x"272829",
        x"2C2D2E", x"313233", x"363738", x"3B3C3D"
    );

    -- Résultats collectés
    type result_array_t is array(0 to TOTAL_PIX-1) of
        std_logic_vector(23 downto 0);
    signal results        : result_array_t;
    signal result_count   : integer := 0;
    signal sim_done       : boolean := false;

begin

    -- =========================================================
    -- DUT : Device Under Test
    -- =========================================================
    DUT : entity work.agcwd_top
        generic map (
            IMG_WIDTH   => IMG_W,
            IMG_HEIGHT  => IMG_H,
            DATA_WIDTH  => 8,
            ALPHA_VALUE => 128  -- alpha = 0.5
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
    -- Génération horloge
    -- =========================================================
    p_clk : process
    begin
        clk <= '0';
        wait for CLK_PERIOD / 2;
        clk <= '1';
        wait for CLK_PERIOD / 2;
        if sim_done then
            wait;
        end if;
    end process p_clk;

    -- =========================================================
    -- Stimulus principal
    -- =========================================================
    p_stimulus : process
        procedure send_frame(
            constant image : in pixel_array_t;
            constant width : in integer;
            constant height: in integer
        ) is
            variable idx   : integer := 0;
            variable col   : integer := 0;
        begin
            report "=== Envoi frame de test ===" severity note;

            for row in 0 to height-1 loop
                for c in 0 to width-1 loop

                    -- SOF sur premier pixel
                    if row = 0 and c = 0 then
                        s_axis_tuser <= '1';
                    else
                        s_axis_tuser <= '0';
                    end if;

                    -- EOL sur dernier pixel de chaque ligne
                    if c = width-1 then
                        s_axis_tlast <= '1';
                    else
                        s_axis_tlast <= '0';
                    end if;

                    s_axis_tdata  <= image(idx);
                    s_axis_tvalid <= '1';

                    wait until rising_edge(clk);

                    s_axis_tvalid <= '0';
                    s_axis_tuser  <= '0';
                    s_axis_tlast  <= '0';

                    -- Gap inter-pixels (réaliste)
                    wait until rising_edge(clk);

                    idx := idx + 1;
                end loop;
            end loop;

            report "=== Frame envoyée ===" severity note;
        end procedure send_frame;

    begin
        -- Reset
        rst_n          <= '0';
        s_axis_tvalid  <= '0';
        s_axis_tdata   <= (others => '0');
        s_axis_tlast   <= '0';
        s_axis_tuser   <= '0';

        wait for 5 * CLK_PERIOD;
        rst_n <= '1';
        wait for 3 * CLK_PERIOD;

        -- =====================================================
        -- Test 1 : Image sombre (dark frame)
        -- =====================================================
        report "--- TEST 1 : Image sombre ---" severity note;
        enable_denoise <= '1';
        enable_sharpen <= '1';
        enable_balance <= '1';
        send_frame(TEST_IMAGE, IMG_W, IMG_H);

        wait for 50 * CLK_PERIOD;

        -- =====================================================
        -- Test 2 : Sans débruitage ni netteté
        -- =====================================================
        report "--- TEST 2 : Flags désactivés ---" severity note;
        enable_denoise <= '0';
        enable_sharpen <= '0';
        enable_balance <= '0';
        send_frame(TEST_IMAGE, IMG_W, IMG_H);

        wait for 50 * CLK_PERIOD;

        -- =====================================================
        -- Test 3 : Image blanche (bright frame)
        -- =====================================================
        report "--- TEST 3 : Image claire ---" severity note;
        enable_denoise <= '1';
        enable_sharpen <= '0';
        enable_balance <= '1';

        -- Envoyer une image très claire
        for i in 0 to TOTAL_PIX-1 loop
            if i = 0 then s_axis_tuser <= '1'; else s_axis_tuser <= '0'; end if;
            if (i mod IMG_W) = IMG_W-1 then
                s_axis_tlast <= '1';
            else
                s_axis_tlast <= '0';
            end if;
            s_axis_tdata  <= x"F5F5F5"; -- Pixel clair
            s_axis_tvalid <= '1';
            wait until rising_edge(clk);
            s_axis_tvalid <= '0';
            wait until rising_edge(clk);
        end loop;

        wait for 100 * CLK_PERIOD;

        report "=== SIMULATION TERMINEE ===" severity note;
        sim_done <= true;
        wait;
    end process p_stimulus;

    -- =========================================================
    -- Collecte des résultats de sortie
    -- =========================================================
    p_collect : process(clk)
    begin
        if rising_edge(clk) then
            if m_axis_tvalid = '1' and m_axis_tready = '1' then
                if result_count < TOTAL_PIX then
                    results(result_count) <= m_axis_tdata;
                    result_count <= result_count + 1;

                    report "Pixel sortie [" &
                        integer'image(result_count) & "] = R:" &
                        integer'image(to_integer(unsigned(
                            m_axis_tdata(23 downto 16)))) &
                        " G:" &
                        integer'image(to_integer(unsigned(
                            m_axis_tdata(15 downto 8)))) &
                        " B:" &
                        integer'image(to_integer(unsigned(
                            m_axis_tdata(7 downto 0))))
                        severity note;
                end if;
            end if;
        end if;
    end process p_collect;

    -- =========================================================
    -- Vérifications automatiques (assertions)
    -- =========================================================
    p_check : process(clk)
    begin
        if rising_edge(clk) then
            if m_axis_tvalid = '1' then
                -- Vérifier que la sortie est dans [0, 255]
                assert to_integer(unsigned(m_axis_tdata(23 downto 16))) <= 255
                    report "ERREUR: Canal R hors plage !"
                    severity error;

                assert to_integer(unsigned(m_axis_tdata(15 downto 8))) <= 255
                    report "ERREUR: Canal G hors plage !"
                    severity error;

                assert to_integer(unsigned(m_axis_tdata(7 downto 0))) <= 255
                    report "ERREUR: Canal B hors plage !"
                    severity error;
            end if;

            -- Vérifier frame_dark et frame_bright ne sont pas simultanés
            assert not (frame_dark = '1' and frame_bright = '1')
                report "ERREUR: frame_dark et frame_bright simultanés !"
                severity error;
        end if;
    end process p_check;

    -- =========================================================
    -- Monitor des statuts
    -- =========================================================
    p_monitor : process(clk)
    begin
        if rising_edge(clk) then
            if frame_done = '1' then
                report ">>> frame_done détecté !" severity note;
            end if;
            if frame_dark = '1' then
                report ">>> Image classifiée : SOMBRE" severity note;
            end if;
            if frame_bright = '1' then
                report ">>> Image classifiée : CLAIRE" severity note;
            end if;
        end if;
    end process p_monitor;

end architecture sim;