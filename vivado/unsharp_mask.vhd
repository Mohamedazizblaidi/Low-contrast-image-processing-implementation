-- =============================================================
-- File: unsharp_mask.vhd
-- Description: Unsharp masking — matches Python implementation:
--   sharpened = 1.4 * original - 0.4 * blurred
--   Gaussian blur kernel sigma=2.0, approx 5x5
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity unsharp_mask is
    generic (
        IMG_WIDTH  : integer := 640;
        DATA_WIDTH : integer := 8
    );
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;
        enable     : in  std_logic;

        s_tdata    : in  std_logic_vector(23 downto 0);
        s_tvalid   : in  std_logic;
        s_tlast    : in  std_logic;
        s_tuser    : in  std_logic;

        m_tdata    : out std_logic_vector(23 downto 0);
        m_tvalid   : out std_logic;
        m_tlast    : out std_logic;
        m_tuser    : out std_logic
    );
end entity unsharp_mask;

architecture rtl of unsharp_mask is

    -- Noyau Gaussien 5x5 pour sigma=2.0, normalisé x256
    -- Calculé avec: G(x,y) = exp(-(x²+y²)/(2*sigma²))
    -- Somme = 256 (pour division par shift)
    type gauss_kernel_t is array(0 to 4, 0 to 4) of integer;
    constant GAUSS_KERNEL : gauss_kernel_t := (
        ( 4,  6,  7,  6,  4),
        ( 6,  9, 10,  9,  6),
        ( 7, 10, 12, 10,  7),
        ( 6,  9, 10,  9,  6),
        ( 4,  6,  7,  6,  4)
    );
    constant GAUSS_SUM : integer := 200; -- Somme des coefficients

    -- Line buffers pour 5x5
    type line_buf_t is array(0 to IMG_WIDTH-1) of std_logic_vector(23 downto 0);
    type line_bufs_t is array(0 to 3) of line_buf_t;
    signal line_bufs : line_bufs_t;

    -- Fenêtre glissante 5x5 (canal par canal)
    type window5_t is array(0 to 4, 0 to 4) of unsigned(7 downto 0);
    signal win_r, win_g, win_b : window5_t;

    signal col_ctr   : integer range 0 to IMG_WIDTH-1 := 0;

    -- Pixel original délayé (2 lignes + 2 colonnes = 2 cycles)
    -- On délaye pour aligner avec la sortie du filtre
    constant PIPE_DEPTH : integer := 8;
    type pipe_data_t is array(0 to PIPE_DEPTH-1) of std_logic_vector(23 downto 0);
    signal pipe_data  : pipe_data_t;
    signal pipe_valid : std_logic_vector(PIPE_DEPTH-1 downto 0);
    signal pipe_last  : std_logic_vector(PIPE_DEPTH-1 downto 0);
    signal pipe_user  : std_logic_vector(PIPE_DEPTH-1 downto 0);

    -- Résultats flou Gaussien
    signal blur_r, blur_g, blur_b : unsigned(7 downto 0);

    -- Résultats unsharp
    signal sharp_r, sharp_g, sharp_b : unsigned(7 downto 0);

    -- Pixel original (délayé)
    signal orig_r, orig_g, orig_b : unsigned(7 downto 0);

begin

    orig_r <= unsigned(pipe_data(PIPE_DEPTH-1)(23 downto 16));
    orig_g <= unsigned(pipe_data(PIPE_DEPTH-1)(15 downto  8));
    orig_b <= unsigned(pipe_data(PIPE_DEPTH-1)( 7 downto  0));

    -- =========================================================
    -- Gestion line buffers et fenêtre 5x5
    -- =========================================================
    p_window : process(clk, rst_n)
    begin
        if rst_n = '0' then
            col_ctr    <= 0;
            pipe_valid <= (others => '0');
            pipe_last  <= (others => '0');
            pipe_user  <= (others => '0');

        elsif rising_edge(clk) then
            -- Pipeline délai
            pipe_valid <= pipe_valid(PIPE_DEPTH-2 downto 0) & s_tvalid;
            pipe_last  <= pipe_last(PIPE_DEPTH-2 downto 0)  & s_tlast;
            pipe_user  <= pipe_user(PIPE_DEPTH-2 downto 0)  & s_tuser;
            pipe_data  <= pipe_data(0 to PIPE_DEPTH-2) & s_tdata;

            if s_tvalid = '1' then
                -- Insérer pixel dans line buffers
                line_bufs(0)(col_ctr) <= s_tdata;
                for i in 1 to 3 loop
                    line_bufs(i)(col_ctr) <= line_bufs(i-1)(col_ctr);
                end loop;

                -- Remplir fenêtre (centre = ligne courante)
                win_r(4)(2) <= unsigned(s_tdata(23 downto 16));
                win_g(4)(2) <= unsigned(s_tdata(15 downto  8));
                win_b(4)(2) <= unsigned(s_tdata( 7 downto  0));

                for row in 0 to 3 loop
                    win_r(row)(2) <=
                        unsigned(line_bufs(3-row)(col_ctr)(23 downto 16));
                    win_g(row)(2) <=
                        unsigned(line_bufs(3-row)(col_ctr)(15 downto  8));
                    win_b(row)(2) <=
                        unsigned(line_bufs(3-row)(col_ctr)( 7 downto  0));
                end loop;

                if col_ctr = IMG_WIDTH - 1 then
                    col_ctr <= 0;
                else
                    col_ctr <= col_ctr + 1;
                end if;
            end if;
        end if;
    end process p_window;

    -- =========================================================
    -- Calcul Flou Gaussien 5x5
    -- =========================================================
    p_gauss : process(clk)
        variable sum_r, sum_g, sum_b : unsigned(15 downto 0);
    begin
        if rising_edge(clk) then
            if pipe_valid(2) = '1' then
                sum_r := (others => '0');
                sum_g := (others => '0');
                sum_b := (others => '0');

                for row in 0 to 4 loop
                    for col in 0 to 4 loop
                        sum_r := sum_r +
                            resize(win_r(row)(col), 16) * GAUSS_KERNEL(row,col);
                        sum_g := sum_g +
                            resize(win_g(row)(col), 16) * GAUSS_KERNEL(row,col);
                        sum_b := sum_b +
                            resize(win_b(row)(col), 16) * GAUSS_KERNEL(row,col);
                    end loop;
                end loop;

                blur_r <= resize(sum_r / GAUSS_SUM, 8);
                blur_g <= resize(sum_g / GAUSS_SUM, 8);
                blur_b <= resize(sum_b / GAUSS_SUM, 8);
            end if;
        end if;
    end process p_gauss;

    -- =========================================================
    -- Unsharp : sharpened = 1.4*orig - 0.4*blur
    -- En entiers : = (14*orig - 4*blur) / 10
    -- =========================================================
    p_unsharp : process(clk)
        variable v_r, v_g, v_b : signed(15 downto 0);
    begin
        if rising_edge(clk) then
            -- Canal R
            v_r := signed("00" & resize(orig_r, 14)) * 14
                 - signed("00" & resize(blur_r, 14)) * 4;
            v_r := v_r / 10;
            if v_r > 255 then sharp_r <= to_unsigned(255, 8);
            elsif v_r < 0 then sharp_r <= to_unsigned(0, 8);
            else sharp_r <= unsigned(v_r(7 downto 0)); end if;

            -- Canal G
            v_g := signed("00" & resize(orig_g, 14)) * 14
                 - signed("00" & resize(blur_g, 14)) * 4;
            v_g := v_g / 10;
            if v_g > 255 then sharp_g <= to_unsigned(255, 8);
            elsif v_g < 0 then sharp_g <= to_unsigned(0, 8);
            else sharp_g <= unsigned(v_g(7 downto 0)); end if;

            -- Canal B
            v_b := signed("00" & resize(orig_b, 14)) * 14
                 - signed("00" & resize(blur_b, 14)) * 4;
            v_b := v_b / 10;
            if v_b > 255 then sharp_b <= to_unsigned(255, 8);
            elsif v_b < 0 then sharp_b <= to_unsigned(0, 8);
            else sharp_b <= unsigned(v_b(7 downto 0)); end if;
        end if;
    end process p_unsharp;

    -- =========================================================
    -- Sortie finale
    -- =========================================================
    m_tdata <= std_logic_vector(sharp_r) &
               std_logic_vector(sharp_g) &
               std_logic_vector(sharp_b) when enable = '1'
               else pipe_data(PIPE_DEPTH-1);

    m_tvalid <= pipe_valid(PIPE_DEPTH-1);
    m_tlast  <= pipe_last(PIPE_DEPTH-1);
    m_tuser  <= pipe_user(PIPE_DEPTH-1);

end architecture rtl;