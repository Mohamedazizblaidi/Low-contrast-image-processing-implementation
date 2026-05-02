-- =============================================================
-- File: channel_stats.vhd
-- Mettre dans : Design Sources
-- Description: Compute per-frame mean and std deviation
--              Classifies frame as dark / bright / normal
-- CORRECTION : fonction isqrt_16 ajoutée dans le package local
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity channel_stats is
    generic (
        IMG_WIDTH  : integer := 640;
        IMG_HEIGHT : integer := 480;
        DATA_WIDTH : integer := 8
    );
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;

        -- Flux pixel RGB
        pixel_in    : in  std_logic_vector(23 downto 0);
        pix_valid   : in  std_logic;
        frame_start : in  std_logic;
        frame_end   : in  std_logic;

        -- Sorties statistiques
        mean_out    : out unsigned(7 downto 0);
        std_out     : out unsigned(7 downto 0);
        is_dark     : out std_logic;
        is_bright   : out std_logic;
        stats_done  : out std_logic
    );
end entity channel_stats;

architecture rtl of channel_stats is

    -- =========================================================
    -- Constantes de classification
    -- =========================================================
    constant DARK_THRESHOLD   : unsigned(7 downto 0) := to_unsigned(5,   8);
    constant BRIGHT_THRESHOLD : unsigned(7 downto 0) := to_unsigned(250, 8);
    constant STD_THRESHOLD    : unsigned(7 downto 0) := to_unsigned(3,   8);

    -- =========================================================
    -- Fonction : racine carrée entière (Newton-Raphson)
    -- Entrée  : valeur 32 bits
    -- Sortie  : racine approchée 16 bits
    -- =========================================================
    function isqrt_32 (val : unsigned(31 downto 0))
        return unsigned is

        variable x    : unsigned(31 downto 0);
        variable x_new: unsigned(31 downto 0);
        variable tmp  : unsigned(63 downto 0);
    begin
        -- Cas trivial
        if val = 0 then
            return to_unsigned(0, 16);
        end if;

        -- Estimation initiale : décalage de 8 bits
        x := shift_right(val, 8) + 1;

        -- 8 itérations Newton-Raphson : x = (x + val/x) / 2
        for i in 0 to 7 loop
            if x = 0 then
                x := to_unsigned(1, 32);
            end if;
            tmp   := resize(val, 64) / resize(x, 64);
            x_new := shift_right(x + tmp(31 downto 0), 1);
            x     := x_new;
        end loop;

        -- Retourner les 16 bits bas (la racine ne dépasse pas 16 bits)
        return x(15 downto 0);
    end function isqrt_32;

    -- =========================================================
    -- Accumulateurs
    -- =========================================================
    -- sum max = 640*480*3*255 = 235,929,600 ? 28 bits suffisent
    signal acc_sum    : unsigned(27 downto 0) := (others => '0');

    -- sum_sq max = 640*480*3*255² = 60,111,948,000 ? 36 bits
    signal acc_sum_sq : unsigned(35 downto 0) := (others => '0');

    -- Compteur pixels (x3 canaux) max = 640*480*3 = 921,600 ? 20 bits
    signal pix_count  : unsigned(19 downto 0) := (others => '0');

    -- =========================================================
    -- Résultats registres
    -- =========================================================
    signal mean_reg   : unsigned(7 downto 0)  := (others => '0');
    signal std_reg    : unsigned(7 downto 0)  := (others => '0');
    signal done_reg   : std_logic             := '0';
    signal dark_reg   : std_logic             := '0';
    signal bright_reg : std_logic             := '0';

    -- =========================================================
    -- Extraction canaux
    -- =========================================================
    signal r_val      : unsigned(7 downto 0);
    signal g_val      : unsigned(7 downto 0);
    signal b_val      : unsigned(7 downto 0);

begin

    -- Extraction directe des canaux depuis le bus 24 bits
    r_val <= unsigned(pixel_in(23 downto 16));
    g_val <= unsigned(pixel_in(15 downto  8));
    b_val <= unsigned(pixel_in( 7 downto  0));

    -- =========================================================
    -- Process : Accumulation sur une frame complète
    -- =========================================================
    p_accumulate : process(clk, rst_n)

        -- Variables locales pour calcul final
        variable v_mean_ext  : unsigned(27 downto 0);
        variable v_mean_sq   : unsigned(27 downto 0);
        variable v_mean8     : unsigned(7  downto 0);
        variable v_esq       : unsigned(35 downto 0);
        variable v_var       : unsigned(35 downto 0);
        variable v_std16     : unsigned(15 downto 0);
        variable v_std8      : unsigned(7  downto 0);

    begin
        if rst_n = '0' then
            acc_sum     <= (others => '0');
            acc_sum_sq  <= (others => '0');
            pix_count   <= (others => '0');
            mean_reg    <= (others => '0');
            std_reg     <= (others => '0');
            done_reg    <= '0';
            dark_reg    <= '0';
            bright_reg  <= '0';

        elsif rising_edge(clk) then

            -- Défaut : done = 0 (pulse 1 cycle)
            done_reg <= '0';

            -- --------------------------------------------------
            -- Remise à zéro en début de frame (SOF)
            -- --------------------------------------------------
            if frame_start = '1' then
                acc_sum    <= (others => '0');
                acc_sum_sq <= (others => '0');
                pix_count  <= (others => '0');
            end if;

            -- --------------------------------------------------
            -- Accumulation pixel valide
            -- --------------------------------------------------
            if pix_valid = '1' then

                -- Accumuler les 3 canaux dans sum
                acc_sum <= acc_sum
                    + resize(r_val, 28)
                    + resize(g_val, 28)
                    + resize(b_val, 28);

                -- Accumuler les carrés
                acc_sum_sq <= acc_sum_sq
                    + resize(r_val * r_val, 36)
                    + resize(g_val * g_val, 36)
                    + resize(b_val * b_val, 36);

                -- Compter 3 échantillons par pixel
                pix_count <= pix_count + 3;

            end if;

            -- --------------------------------------------------
            -- Fin de frame : calcul mean et std
            -- --------------------------------------------------
            if frame_end = '1' and pix_valid = '1' then

                if pix_count > 0 then

                    -- mean = acc_sum / pix_count
                    v_mean_ext := acc_sum / pix_count;
                    v_mean8    := v_mean_ext(7 downto 0);
                    mean_reg   <= v_mean8;

                    -- E[X²] = acc_sum_sq / pix_count
                    v_esq := acc_sum_sq / pix_count;

                    -- mean² (pour soustraire)
                    v_mean_sq := resize(v_mean8 * v_mean8, 28);

                    -- var = E[X²] - mean²   (clamp à 0)
                    if v_esq >= resize(v_mean_sq, 36) then
                        v_var := v_esq - resize(v_mean_sq, 36);
                    else
                        v_var := (others => '0');
                    end if;

                    -- std = isqrt(var)
                    -- var est sur 36 bits mais la variance
                    -- d'une image uint8 ne dépasse pas 255²=65025
                    -- ? les 16 bits hauts sont toujours 0
                    v_std16 := isqrt_32(
                        resize(v_var(15 downto 0), 32)
                    );

                    -- Saturer à 255
                    if v_std16 > 255 then
                        v_std8 := to_unsigned(255, 8);
                    else
                        v_std8 := v_std16(7 downto 0);
                    end if;
                    std_reg <= v_std8;

                    -- ------------------------------------------
                    -- Classification
                    -- ------------------------------------------
                    if (v_mean8 <= DARK_THRESHOLD) and
                       (v_std8  <  STD_THRESHOLD)  then
                        dark_reg   <= '1';
                        bright_reg <= '0';

                    elsif (v_mean8 >= BRIGHT_THRESHOLD) and
                          (v_std8  <  STD_THRESHOLD)    then
                        dark_reg   <= '0';
                        bright_reg <= '1';

                    else
                        dark_reg   <= '0';
                        bright_reg <= '0';
                    end if;

                end if;

                -- Signal done (1 cycle)
                done_reg <= '1';

            end if;
        end if;
    end process p_accumulate;

    -- =========================================================
    -- Assignation des sorties
    -- =========================================================
    mean_out   <= mean_reg;
    std_out    <= std_reg;
    is_dark    <= dark_reg;
    is_bright  <= bright_reg;
    stats_done <= done_reg;

end architecture rtl;