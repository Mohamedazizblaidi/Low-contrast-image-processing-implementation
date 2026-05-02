-- =============================================================
-- File: cdf_engine.vhd
-- Description: Compute CDF from weighted PDF and generate
--              the gamma correction LUT.
--   gamma_lut[i] = round((i/255)^(1 - CDF[i]) * 255)
--   Output: 256-entry LUT of uint8
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cdf_engine is
    generic (
        DATA_WIDTH : integer := 8
    );
    port (
        clk          : in  std_logic;
        rst_n        : in  std_logic;

        -- Interface weighted PDF RAM
        wpdf_done    : in  std_logic;
        wpdf_rd_addr : out unsigned(7 downto 0);
        wpdf_rd_data : in  unsigned(15 downto 0); -- Q0.16

        -- Sortie : LUT gamma
        lut_wr_en    : out std_logic;
        lut_wr_addr  : out unsigned(7 downto 0);
        lut_wr_data  : out unsigned(7 downto 0);
        lut_done     : out std_logic
    );
end entity cdf_engine;

architecture rtl of cdf_engine is

    type state_t is (ST_IDLE, ST_ACCUMULATE, ST_WAIT_ACC,
                     ST_NORMALIZE, ST_GEN_LUT, ST_WAIT_LUT, ST_DONE);
    signal state : state_t := ST_IDLE;

    -- CDF accumulatrice (Q8.16 pour garder la précision)
    signal cdf_acc       : unsigned(23 downto 0);
    signal wpdf_sum      : unsigned(23 downto 0); -- Somme totale du wpdf
    signal bin_idx       : unsigned(8 downto 0);

    -- RAM CDF intermédiaire (256 x 24 bits)
    type cdf_ram_t is array(0 to 255) of unsigned(23 downto 0);
    signal cdf_ram       : cdf_ram_t;

    -- Normalisation
    signal cdf_norm      : unsigned(15 downto 0); -- Q0.16 [0,1]

    -- Gamma = 1 - CDF  (clampé à [0.01, 1.0])
    signal gamma_q16     : unsigned(15 downto 0);

    -- i/255 en Q0.16
    signal norm_i_q16    : unsigned(15 downto 0);

    -- Table précalculée (i/255) * 255 = i (identité pour LUT)
    -- En réalité : output = i^gamma * 255
    -- Approximation : pow(x, gamma) via exp(gamma * ln(x))
    -- Pour FPGA : table BRAM log2 + multiplication + exp2

    -- Registre résultat LUT
    signal lut_val       : unsigned(7 downto 0);

begin

    p_fsm : process(clk, rst_n)
        variable v_wpdf      : unsigned(15 downto 0);
        variable v_cdf_norm  : unsigned(15 downto 0);
        variable v_gamma     : unsigned(15 downto 0);
        variable v_input_i   : unsigned(15 downto 0);
        variable v_output    : unsigned(15 downto 0);
    begin
        if rst_n = '0' then
            state        <= ST_IDLE;
            cdf_acc      <= (others => '0');
            wpdf_sum     <= (others => '0');
            bin_idx      <= (others => '0');
            lut_wr_en    <= '0';
            lut_done     <= '0';

        elsif rising_edge(clk) then
            lut_wr_en <= '0';
            lut_done  <= '0';

            case state is

                when ST_IDLE =>
                    if wpdf_done = '1' then
                        cdf_acc  <= (others => '0');
                        wpdf_sum <= (others => '0');
                        bin_idx  <= (others => '0');
                        state    <= ST_ACCUMULATE;
                    end if;

                -- =============================================
                -- Passe 1 : CDF = cumulative sum of wpdf
                -- =============================================
                when ST_ACCUMULATE =>
                    wpdf_rd_addr <= bin_idx(7 downto 0);
                    state        <= ST_WAIT_ACC;

                when ST_WAIT_ACC =>
                    v_wpdf  := wpdf_rd_data;
                    cdf_acc <= cdf_acc + resize(v_wpdf, 24);
                    cdf_ram(to_integer(bin_idx(7 downto 0))) <= cdf_acc;
                    wpdf_sum <= wpdf_sum + resize(v_wpdf, 24);

                    if bin_idx = 255 then
                        bin_idx <= (others => '0');
                        state   <= ST_GEN_LUT;
                    else
                        bin_idx <= bin_idx + 1;
                        state   <= ST_ACCUMULATE;
                    end if;

                -- =============================================
                -- Passe 2 : Générer LUT gamma
                -- =============================================
                when ST_GEN_LUT =>
                    -- cdf_norm = cdf[i] / wpdf_sum  → Q0.16
                    if wpdf_sum > 0 then
                        v_cdf_norm := resize(
                            shift_left(cdf_ram(to_integer(bin_idx(7 downto 0))), 16)
                            / wpdf_sum,
                            16);
                    else
                        v_cdf_norm := (others => '0');
                    end if;

                    -- gamma = 1.0 - cdf_norm, clampé à [0.01, 1.0]
                    if v_cdf_norm >= x"FFCC" then  -- 0.99 en Q0.16
                        v_gamma := to_unsigned(164, 16); -- 0.0025 ≈ 1/400
                    else
                        v_gamma := x"FFFF" - v_cdf_norm;
                    end if;

                    -- i_norm = bin_idx / 255  (Q0.16)
                    v_input_i := resize(
                        shift_left(resize(bin_idx, 32), 16) / 255,
                        16);

                    -- output = pow(i_norm, gamma) * 255
                    -- Approximation LUT pow ou CORDIC
                    v_output := approx_pow_q16(v_input_i, v_gamma);

                    -- Écriture LUT
                    lut_wr_en   <= '1';
                    lut_wr_addr <= bin_idx(7 downto 0);
                    lut_wr_data <= v_output(15 downto 8); -- Q8.8 → uint8

                    if bin_idx = 255 then
                        state <= ST_DONE;
                    else
                        bin_idx <= bin_idx + 1;
                    end if;

                when ST_DONE =>
                    lut_done <= '1';
                    state    <= ST_IDLE;

                when others =>
                    state <= ST_IDLE;
            end case;
        end if;
    end process p_fsm;

end architecture rtl;