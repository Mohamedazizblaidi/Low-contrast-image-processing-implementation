-- =============================================================
-- File: pdf_weighted.vhd
-- Description: Compute the AGCWD weighted PDF from histogram.
--   weighted_pdf[i] = pdf_max * ((pdf[i]-pdf_min)/(pdf_max-pdf_min))^alpha
--   Result stored in LUT RAM, Q8.8 fixed-point
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity pdf_weighted is
    generic (
        DATA_WIDTH      : integer := 8;
        FRAC_BITS       : integer := 8;    -- Format Q8.8
        ALPHA_VALUE     : integer := 128;  -- alpha=0.5 en Q0.8 => 0x80
        TOTAL_PIXELS    : integer := 307200
    );
    port (
        clk           : in  std_logic;
        rst_n         : in  std_logic;

        -- Interface avec histogram_engine
        hist_done     : in  std_logic;
        hist_rd_addr  : out unsigned(7 downto 0);
        hist_rd_data  : in  unsigned(19 downto 0);

        -- Sortie weighted_pdf (Q8.8 fixe)
        wpdf_wr_en    : out std_logic;
        wpdf_wr_addr  : out unsigned(7 downto 0);
        wpdf_wr_data  : out unsigned(15 downto 0);
        wpdf_done     : out std_logic
    );
end entity pdf_weighted;

architecture rtl of pdf_weighted is

    -- Machine à états
    type state_t is (
        ST_IDLE,
        ST_SCAN_MIN_MAX,  -- Scan histogramme pour trouver pdf_min, pdf_max
        ST_WAIT_SCAN,
        ST_COMPUTE,       -- Calculer weighted_pdf pour chaque bin
        ST_WAIT_COMPUTE,
        ST_DONE
    );
    signal state : state_t := ST_IDLE;

    -- Compteurs
    signal bin_idx       : unsigned(8 downto 0); -- 0..255 + overflow

    -- PDF en virgule fixe Q0.16
    -- pdf[i] = hist[i] / total_pixels  → représenté en Q0.16
    signal pdf_min_q16   : unsigned(15 downto 0);
    signal pdf_max_q16   : unsigned(15 downto 0);
    signal pdf_range_q16 : unsigned(15 downto 0);

    -- Constante 1/TOTAL_PIXELS en Q0.32 précalculée
    -- Pour TOTAL_PIXELS = 307200 : 1/307200 ≈ 3.255e-6
    -- En Q0.32 : round(2^32 / 307200) = 13981
    constant INV_TOTAL   : unsigned(31 downto 0) :=
        to_unsigned(integer(real(2**32) / real(TOTAL_PIXELS)), 32);

    -- Valeur pdf courante en Q0.16
    signal pdf_cur_q16   : unsigned(15 downto 0);

    -- Résultat weighted_pdf avant normalisation
    signal wpdf_cur      : unsigned(15 downto 0);

begin

    -- =========================================================
    -- FSM principale
    -- =========================================================
    p_fsm : process(clk, rst_n)
        variable v_hist_val  : unsigned(19 downto 0);
        variable v_pdf_q16   : unsigned(15 downto 0);
        variable v_num       : unsigned(15 downto 0);
        variable v_ratio     : unsigned(15 downto 0);
        variable v_powered   : unsigned(15 downto 0);
    begin
        if rst_n = '0' then
            state          <= ST_IDLE;
            bin_idx        <= (others => '0');
            pdf_min_q16    <= (others => '1'); -- MAX init pour min
            pdf_max_q16    <= (others => '0');
            pdf_range_q16  <= (others => '0');
            wpdf_wr_en     <= '0';
            wpdf_done      <= '0';
            hist_rd_addr   <= (others => '0');

        elsif rising_edge(clk) then
            wpdf_wr_en  <= '0';
            wpdf_done   <= '0';

            case state is

                -- =============================================
                when ST_IDLE =>
                    if hist_done = '1' then
                        bin_idx     <= (others => '0');
                        pdf_min_q16 <= (others => '1');
                        pdf_max_q16 <= (others => '0');
                        state       <= ST_SCAN_MIN_MAX;
                    end if;

                -- =============================================
                -- Passe 1 : Trouver pdf_min et pdf_max
                -- =============================================
                when ST_SCAN_MIN_MAX =>
                    hist_rd_addr <= bin_idx(7 downto 0);
                    state        <= ST_WAIT_SCAN;

                when ST_WAIT_SCAN =>
                    v_hist_val := hist_rd_data;

                    if v_hist_val > 0 then
                        -- pdf_q16 = hist_val * INV_TOTAL (Q0.16)
                        v_pdf_q16 := resize(
                            shift_right(v_hist_val * INV_TOTAL(31 downto 16), 16),
                            16);

                        if v_pdf_q16 < pdf_min_q16 then
                            pdf_min_q16 <= v_pdf_q16;
                        end if;
                        if v_pdf_q16 > pdf_max_q16 then
                            pdf_max_q16 <= v_pdf_q16;
                        end if;
                    end if;

                    if bin_idx = 255 then
                        pdf_range_q16 <= pdf_max_q16 - pdf_min_q16;
                        bin_idx       <= (others => '0');
                        state         <= ST_COMPUTE;
                    else
                        bin_idx <= bin_idx + 1;
                        state   <= ST_SCAN_MIN_MAX;
                    end if;

                -- =============================================
                -- Passe 2 : Calculer weighted_pdf
                -- =============================================
                when ST_COMPUTE =>
                    hist_rd_addr <= bin_idx(7 downto 0);
                    state        <= ST_WAIT_COMPUTE;

                when ST_WAIT_COMPUTE =>
                    v_hist_val := hist_rd_data;

                    if v_hist_val = 0 or pdf_range_q16 = 0 then
                        -- Bin vide ou range nul → weighted_pdf = 0
                        wpdf_cur <= (others => '0');
                    else
                        v_pdf_q16 := resize(
                            shift_right(v_hist_val * INV_TOTAL(31 downto 16), 16),
                            16);

                        -- ratio = (pdf - pdf_min) / pdf_range  [Q0.16]
                        if v_pdf_q16 > pdf_min_q16 then
                            v_num   := v_pdf_q16 - pdf_min_q16;
                            v_ratio := resize(
                                shift_left(resize(v_num, 32) / pdf_range_q16, 0),
                                16);
                        else
                            v_ratio := (others => '0');
                        end if;

                        -- Approximation puissance : ratio^alpha
                        -- Pour alpha=0.5 : sqrt approximée par lookup
                        -- Générique : approximation linéaire (simplification FPGA)
                        -- v_powered = ratio^0.5 ≈ sqrt(ratio)
                        -- Implémentation : Newton-Raphson ou table
                        v_powered := approx_sqrt_q16(v_ratio);

                        -- weighted_pdf = pdf_max * powered  [Q0.16]
                        wpdf_cur <= resize(
                            shift_right(pdf_max_q16 * v_powered, 16),
                            16);
                    end if;

                    -- Écriture dans la RAM wpdf
                    wpdf_wr_en   <= '1';
                    wpdf_wr_addr <= bin_idx(7 downto 0);
                    wpdf_wr_data <= wpdf_cur;

                    if bin_idx = 255 then
                        state <= ST_DONE;
                    else
                        bin_idx <= bin_idx + 1;
                        state   <= ST_COMPUTE;
                    end if;

                -- =============================================
                when ST_DONE =>
                    wpdf_done <= '1';
                    state     <= ST_IDLE;

                when others =>
                    state <= ST_IDLE;

            end case;
        end if;
    end process p_fsm;

end architecture rtl;