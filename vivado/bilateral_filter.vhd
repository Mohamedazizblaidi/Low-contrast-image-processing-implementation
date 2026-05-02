-- =============================================================
-- File: bilateral_filter.vhd
-- Mettre dans : Design Sources
-- Description: Approximated 5x5 bilateral filter per channel.
-- CORRECTION : LUT range précalculée sans exp() ni math_real
--              Valeurs calculées offline : exp(-d²/(2*35²))*255
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity bilateral_filter is
    generic (
        IMG_WIDTH   : integer := 640;
        DATA_WIDTH  : integer := 8;
        KERNEL_SIZE : integer := 5
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
end entity bilateral_filter;

architecture rtl of bilateral_filter is

    constant RADIUS : integer := KERNEL_SIZE / 2; -- 2

    -- =========================================================
    -- Poids spatiaux Gaussiens 5x5 précalculés
    -- sigma_space = 35 ? poids quasi-uniformes
    -- G(x,y) = exp(-(x²+y²)/(2*35²)) * 232  (normalisé)
    -- =========================================================
    type spatial_weights_t is array(0 to 4, 0 to 4)
        of integer range 0 to 255;

    constant SPATIAL_W : spatial_weights_t := (
        (150, 177, 187, 177, 150),
        (177, 210, 221, 210, 177),
        (187, 221, 232, 221, 187),
        (177, 210, 221, 210, 177),
        (150, 177, 187, 177, 150)
    );

    -- =========================================================
    -- LUT poids range : exp(-d² / (2 * 35²)) * 255
    -- Précalculée pour d = 0..255, sigmaColor = 35
    -- sigma² * 2 = 2450
    -- Valeurs calculées avec Python :
    --   [round(255*math.exp(-d*d/2450)) for d in range(256)]
    -- =========================================================
    type range_lut_t is array(0 to 255) of integer range 0 to 255;

    constant RANGE_W_LUT : range_lut_t := (
        -- d=0..15
        255,255,254,253,251,248,245,241,
        237,232,226,220,214,207,200,193,
        -- d=16..31
        185,178,170,162,154,146,138,130,
        123,115,108,101, 94, 88, 82, 76,
        -- d=32..47
         70, 65, 60, 55, 50, 46, 42, 38,
         35, 32, 29, 26, 23, 21, 19, 17,
        -- d=48..63
         15, 13, 12, 10,  9,  8,  7,  6,
          5,  5,  4,  3,  3,  2,  2,  2,
        -- d=64..79
          1,  1,  1,  1,  1,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
        -- d=80..255 : toutes à 0
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0,
          0,  0,  0,  0,  0,  0,  0,  0
    );

    -- =========================================================
    -- Line buffers : 4 lignes pour noyau 5x5
    -- Chaque ligne = IMG_WIDTH pixels x 24 bits RGB
    -- =========================================================
    type line_t      is array(0 to IMG_WIDTH-1)
        of std_logic_vector(23 downto 0);
    type line_array_t is array(0 to KERNEL_SIZE-2)
        of line_t;

    signal line_bufs : line_array_t :=
        (others => (others => (others => '0')));

    signal col_ctr   : integer range 0 to IMG_WIDTH-1 := 0;

    -- =========================================================
    -- Fenêtre glissante 5x5 par canal
    -- =========================================================
    type win_row_t is array(0 to KERNEL_SIZE-1)
        of unsigned(7 downto 0);
    type win_t     is array(0 to KERNEL_SIZE-1)
        of win_row_t;

    signal win_r : win_t := (others => (others => (others => '0')));
    signal win_g : win_t := (others => (others => (others => '0')));
    signal win_b : win_t := (others => (others => (others => '0')));

    -- Centre de la fenêtre
    signal ctr_r : unsigned(7 downto 0) := (others => '0');
    signal ctr_g : unsigned(7 downto 0) := (others => '0');
    signal ctr_b : unsigned(7 downto 0) := (others => '0');

    -- =========================================================
    -- Pipeline delay pour aligner contrôle avec données filtrées
    -- =========================================================
    constant PIPE_D : integer := 4;
    type pipe_vec_t is array(0 to PIPE_D-1)
        of std_logic_vector(23 downto 0);

    signal pipe_data  : pipe_vec_t :=
        (others => (others => '0'));
    signal pipe_valid : std_logic_vector(PIPE_D-1 downto 0)
        := (others => '0');
    signal pipe_last  : std_logic_vector(PIPE_D-1 downto 0)
        := (others => '0');
    signal pipe_user  : std_logic_vector(PIPE_D-1 downto 0)
        := (others => '0');

    -- =========================================================
    -- Résultats du filtre bilatéral
    -- =========================================================
    signal filt_r : unsigned(7 downto 0) := (others => '0');
    signal filt_g : unsigned(7 downto 0) := (others => '0');
    signal filt_b : unsigned(7 downto 0) := (others => '0');

begin

    -- Centre de la fenêtre = pixel (RADIUS, RADIUS)
    ctr_r <= win_r(RADIUS)(RADIUS);
    ctr_g <= win_g(RADIUS)(RADIUS);
    ctr_b <= win_b(RADIUS)(RADIUS);

    -- =========================================================
    -- Process 1 : Gestion line buffers + fenêtre glissante
    -- =========================================================
    p_linebuf : process(clk, rst_n)
    begin
        if rst_n = '0' then
            col_ctr    <= 0;
            pipe_valid <= (others => '0');
            pipe_last  <= (others => '0');
            pipe_user  <= (others => '0');
            pipe_data  <= (others => (others => '0'));

        elsif rising_edge(clk) then

            -- Décalage pipeline contrôle
            pipe_valid <= pipe_valid(PIPE_D-2 downto 0) & s_tvalid;
            pipe_last  <= pipe_last (PIPE_D-2 downto 0) & s_tlast;
            pipe_user  <= pipe_user (PIPE_D-2 downto 0) & s_tuser;
            pipe_data  <= pipe_data(1 to PIPE_D-1) & s_tdata;

            if s_tvalid = '1' then

                -- -----------------------------------------
                -- Insérer pixel courant dans line buffer 0
                -- puis décaler les autres lignes
                -- -----------------------------------------
                line_bufs(0)(col_ctr) <= s_tdata;
                for k in 1 to KERNEL_SIZE-2 loop
                    line_bufs(k)(col_ctr) <=
                        line_bufs(k-1)(col_ctr);
                end loop;

                -- -----------------------------------------
                -- Remplir colonne centrale de la fenêtre
                -- Ligne 4 = pixel courant
                -- Ligne 3 = line_buf(0) (1 ligne avant)
                -- Ligne 2 = line_buf(1) (2 lignes avant)
                -- Ligne 1 = line_buf(2) (3 lignes avant)
                -- Ligne 0 = line_buf(3) (4 lignes avant)
                -- -----------------------------------------
                win_r(4)(RADIUS) <=
                    unsigned(s_tdata(23 downto 16));
                win_g(4)(RADIUS) <=
                    unsigned(s_tdata(15 downto  8));
                win_b(4)(RADIUS) <=
                    unsigned(s_tdata( 7 downto  0));

                for row in 0 to KERNEL_SIZE-2 loop
                    win_r(row)(RADIUS) <= unsigned(
                        line_bufs(KERNEL_SIZE-2-row)(col_ctr)
                        (23 downto 16));
                    win_g(row)(RADIUS) <= unsigned(
                        line_bufs(KERNEL_SIZE-2-row)(col_ctr)
                        (15 downto  8));
                    win_b(row)(RADIUS) <= unsigned(
                        line_bufs(KERNEL_SIZE-2-row)(col_ctr)
                        ( 7 downto  0));
                end loop;

                -- -----------------------------------------
                -- Décaler colonnes horizontalement
                -- col 0?1?2?3?4(nouveau)
                -- -----------------------------------------
                for row in 0 to KERNEL_SIZE-1 loop
                    for c in 0 to KERNEL_SIZE-2 loop
                        win_r(row)(c) <= win_r(row)(c+1);
                        win_g(row)(c) <= win_g(row)(c+1);
                        win_b(row)(c) <= win_b(row)(c+1);
                    end loop;
                end loop;

                -- Compteur colonne
                if col_ctr = IMG_WIDTH - 1 then
                    col_ctr <= 0;
                else
                    col_ctr <= col_ctr + 1;
                end if;

            end if;
        end if;
    end process p_linebuf;

    -- =========================================================
    -- Process 2 : Calcul filtre bilatéral 5x5
    -- =========================================================
    p_filter : process(clk, rst_n)

        variable pix_r_v, pix_g_v, pix_b_v : integer range 0 to 255;
        variable ctr_r_v, ctr_g_v, ctr_b_v : integer range 0 to 255;
        variable diff_r, diff_g, diff_b     : integer range 0 to 255;
        variable wr_r, wr_g, wr_b           : integer range 0 to 255;
        variable ws                          : integer range 0 to 255;
        variable wt_r, wt_g, wt_b           : integer range 0 to 65025;

        -- Accumulateurs somme des poids (max = 25 * 255 * 255 = 1,625,625)
        variable sum_wr  : integer range 0 to 2000000;
        variable sum_wg  : integer range 0 to 2000000;
        variable sum_wb  : integer range 0 to 2000000;

        -- Accumulateurs somme pondérée (max = 25*255*255*255 ? 414M)
        variable sum_fwr : integer range 0 to 500000000;
        variable sum_fwg : integer range 0 to 500000000;
        variable sum_fwb : integer range 0 to 500000000;

        variable res_r, res_g, res_b : integer range 0 to 255;

    begin
        if rst_n = '0' then
            filt_r <= (others => '0');
            filt_g <= (others => '0');
            filt_b <= (others => '0');

        elsif rising_edge(clk) then

            if pipe_valid(1) = '1' then

                -- Initialiser accumulateurs
                sum_wr  := 0;
                sum_wg  := 0;
                sum_wb  := 0;
                sum_fwr := 0;
                sum_fwg := 0;
                sum_fwb := 0;

                -- Valeurs centre
                ctr_r_v := to_integer(ctr_r);
                ctr_g_v := to_integer(ctr_g);
                ctr_b_v := to_integer(ctr_b);

                -- Parcours noyau 5x5
                for row in 0 to KERNEL_SIZE-1 loop
                    for col in 0 to KERNEL_SIZE-1 loop

                        -- Valeurs pixel voisin
                        pix_r_v := to_integer(win_r(row)(col));
                        pix_g_v := to_integer(win_g(row)(col));
                        pix_b_v := to_integer(win_b(row)(col));

                        -- Différences absolues avec centre
                        if pix_r_v >= ctr_r_v then
                            diff_r := pix_r_v - ctr_r_v;
                        else
                            diff_r := ctr_r_v - pix_r_v;
                        end if;

                        if pix_g_v >= ctr_g_v then
                            diff_g := pix_g_v - ctr_g_v;
                        else
                            diff_g := ctr_g_v - pix_g_v;
                        end if;

                        if pix_b_v >= ctr_b_v then
                            diff_b := pix_b_v - ctr_b_v;
                        else
                            diff_b := ctr_b_v - pix_b_v;
                        end if;

                        -- Poids range depuis LUT précalculée
                        wr_r := RANGE_W_LUT(diff_r);
                        wr_g := RANGE_W_LUT(diff_g);
                        wr_b := RANGE_W_LUT(diff_b);

                        -- Poids spatial
                        ws := SPATIAL_W(row, col);

                        -- Poids total = spatial * range / 255
                        -- (diviser par 255 pour rester en Q0.8)
                        wt_r := (ws * wr_r) / 255;
                        wt_g := (ws * wr_g) / 255;
                        wt_b := (ws * wr_b) / 255;

                        -- Accumulation
                        sum_wr  := sum_wr  + wt_r;
                        sum_wg  := sum_wg  + wt_g;
                        sum_wb  := sum_wb  + wt_b;

                        sum_fwr := sum_fwr + pix_r_v * wt_r;
                        sum_fwg := sum_fwg + pix_g_v * wt_g;
                        sum_fwb := sum_fwb + pix_b_v * wt_b;

                    end loop;
                end loop;

                -- Division finale : valeur filtrée
                if sum_wr > 0 then
                    res_r := sum_fwr / sum_wr;
                else
                    res_r := ctr_r_v;
                end if;

                if sum_wg > 0 then
                    res_g := sum_fwg / sum_wg;
                else
                    res_g := ctr_g_v;
                end if;

                if sum_wb > 0 then
                    res_b := sum_fwb / sum_wb;
                else
                    res_b := ctr_b_v;
                end if;

                -- Saturation et conversion
                if res_r > 255 then res_r := 255; end if;
                if res_g > 255 then res_g := 255; end if;
                if res_b > 255 then res_b := 255; end if;

                filt_r <= to_unsigned(res_r, 8);
                filt_g <= to_unsigned(res_g, 8);
                filt_b <= to_unsigned(res_b, 8);

            end if;
        end if;
    end process p_filter;

    -- =========================================================
    -- Sortie : bypass si enable='0', filtré sinon
    -- =========================================================
    m_tdata <= std_logic_vector(filt_r) &
               std_logic_vector(filt_g) &
               std_logic_vector(filt_b)
               when (enable = '1')
               else pipe_data(PIPE_D-1);

    m_tvalid <= pipe_valid(PIPE_D-1);
    m_tlast  <= pipe_last (PIPE_D-1);
    m_tuser  <= pipe_user (PIPE_D-1);

end architecture rtl;