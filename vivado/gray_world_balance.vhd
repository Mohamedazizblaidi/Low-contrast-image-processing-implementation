library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gray_world_balance is
    generic (
        IMG_WIDTH  : integer := 640;
        IMG_HEIGHT : integer := 480;
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
end entity gray_world_balance;

architecture rtl of gray_world_balance is

    constant TOTAL_PIXELS : integer := IMG_WIDTH * IMG_HEIGHT;
    -- Nombre de bits pour accumulateurs
    constant ACC_BITS     : integer := 28; -- 640*480*255 < 2^28

    -- Accumulateurs somme par canal
    signal acc_r          : unsigned(ACC_BITS-1 downto 0);
    signal acc_g          : unsigned(ACC_BITS-1 downto 0);
    signal acc_b          : unsigned(ACC_BITS-1 downto 0);
    signal pix_count      : unsigned(23 downto 0);
    signal row_count      : integer range 0 to IMG_HEIGHT-1 := 0;

    -- Moyennes par canal (Q8.8)
    signal mean_r         : unsigned(15 downto 0);
    signal mean_g         : unsigned(15 downto 0);
    signal mean_b         : unsigned(15 downto 0);
    signal global_mean    : unsigned(15 downto 0);

    -- Gains Q8.8 (gain = global_mean / mean_c)
    signal gain_r         : unsigned(15 downto 0);
    signal gain_g         : unsigned(15 downto 0);
    signal gain_b         : unsigned(15 downto 0);
    signal gains_ready    : std_logic := '0';

    -- Canaux d'entree
    signal in_r           : unsigned(7 downto 0);
    signal in_g           : unsigned(7 downto 0);
    signal in_b           : unsigned(7 downto 0);

    -- Sortie corrigee
    signal out_r          : unsigned(7 downto 0);
    signal out_g          : unsigned(7 downto 0);
    signal out_b          : unsigned(7 downto 0);

    -- Seuil difference de moyennes : > 30 pour corriger
    constant MEAN_DIFF_THRESHOLD : unsigned(7 downto 0) := to_unsigned(30, 8);
    signal apply_balance  : std_logic := '0';

begin

    in_r <= unsigned(s_tdata(23 downto 16));
    in_g <= unsigned(s_tdata(15 downto  8));
    in_b <= unsigned(s_tdata( 7 downto  0));

    -- =========================================================
    -- Process : Accumulation moyennes
    -- =========================================================
    p_accumulate : process(clk, rst_n)
        variable v_mean_r, v_mean_g, v_mean_b : unsigned(15 downto 0);
        variable v_global : unsigned(17 downto 0);
        variable v_max_m, v_min_m : unsigned(15 downto 0);
    begin
        if rst_n = '0' then
            acc_r       <= (others => '0');
            acc_g       <= (others => '0');
            acc_b       <= (others => '0');
            pix_count   <= (others => '0');
            row_count   <= 0;
            gains_ready <= '0';
            apply_balance <= '0';
            gain_r      <= x"0100"; -- 1.0 en Q8.8
            gain_g      <= x"0100";
            gain_b      <= x"0100";

        elsif rising_edge(clk) then
            gains_ready <= '0';

            if s_tuser = '1' then
                acc_r     <= (others => '0');
                acc_g     <= (others => '0');
                acc_b     <= (others => '0');
                pix_count <= (others => '0');
                row_count <= 0;
            end if;

            if s_tvalid = '1' then
                acc_r     <= acc_r + resize(in_r, ACC_BITS);
                acc_g     <= acc_g + resize(in_g, ACC_BITS);
                acc_b     <= acc_b + resize(in_b, ACC_BITS);
                pix_count <= pix_count + 1;
            end if;

            -- Fin de frame : calculer les gains
            if s_tlast = '1' and s_tvalid = '1' then
                
                if row_count < IMG_HEIGHT-1 then
                    row_count <= row_count + 1;
                end if;

                -- Trigger calculation ONLY at the end of the last row
                if row_count = IMG_HEIGHT - 1 then
                    if pix_count > 0 then
                        -- Moyennes Q8.8
                        v_mean_r := resize(shift_left(acc_r, 8) / pix_count, 16);
                        v_mean_g := resize(shift_left(acc_g, 8) / pix_count, 16);
                        v_mean_b := resize(shift_left(acc_b, 8) / pix_count, 16);

                        mean_r <= v_mean_r;
                        mean_g <= v_mean_g;
                        mean_b <= v_mean_b;

                        -- Moyenne globale Q8.8
                        v_global := resize(v_mean_r, 18)
                                  + resize(v_mean_g, 18)
                                  + resize(v_mean_b, 18);
                        global_mean <= resize(v_global / 3, 16);

                        -- Verifier si correction necessaire
                        if v_mean_r >= v_mean_g and v_mean_r >= v_mean_b then
                            v_max_m := v_mean_r;
                        elsif v_mean_g >= v_mean_b then
                            v_max_m := v_mean_g;
                        else
                            v_max_m := v_mean_b;
                        end if;

                        if v_mean_r <= v_mean_g and v_mean_r <= v_mean_b then
                            v_min_m := v_mean_r;
                        elsif v_mean_g <= v_mean_b then
                            v_min_m := v_mean_g;
                        else
                            v_min_m := v_mean_b;
                        end if;

                        -- Difference en unites Q8.8 -> entier pixels : decalage de 8
                        if shift_right(v_max_m - v_min_m, 8) >
                           resize(MEAN_DIFF_THRESHOLD, 16) then
                            apply_balance <= '1';

                            -- Gains Q8.8 : global_mean / mean_c
                            if v_mean_r > 0 then
                                gain_r <= resize(shift_left(
                                    resize(v_global/3, 32) / v_mean_r, 0), 16);
                            else
                                gain_r <= x"0100";
                            end if;

                            if v_mean_g > 0 then
                                gain_g <= resize(shift_left(
                                    resize(v_global/3, 32) / v_mean_g, 0), 16);
                            else
                                gain_g <= x"0100";
                            end if;

                            if v_mean_b > 0 then
                                gain_b <= resize(shift_left(
                                    resize(v_global/3, 32) / v_mean_b, 0), 16);
                            else
                                gain_b <= x"0100";
                            end if;
                        else
                            apply_balance <= '0';
                            gain_r <= x"0100";
                            gain_g <= x"0100";
                            gain_b <= x"0100";
                        end if;

                        gains_ready <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process p_accumulate;

    -- =========================================================
    -- Process : Application des gains
    -- =========================================================
    p_apply : process(clk, rst_n)
        variable v_r, v_g, v_b : unsigned(23 downto 0);
    begin
        if rst_n = '0' then
            out_r    <= (others => '0');
            out_g    <= (others => '0');
            out_b    <= (others => '0');
            m_tvalid <= '0';
            m_tlast  <= '0';
            m_tuser  <= '0';

        elsif rising_edge(clk) then
            m_tvalid <= s_tvalid;
            m_tlast  <= s_tlast;
            m_tuser  <= s_tuser;

            if s_tvalid = '1' then
                if enable = '1' and apply_balance = '1' then
                    -- Appliquer gain Q8.8 et saturer a 255
                    v_r := resize(shift_right(in_r * gain_r, 8), 24);
                    v_g := resize(shift_right(in_g * gain_g, 8), 24);
                    v_b := resize(shift_right(in_b * gain_b, 8), 24);

                    if v_r > 255 then out_r <= to_unsigned(255, 8);
                    else out_r <= v_r(7 downto 0); end if;

                    if v_g > 255 then out_g <= to_unsigned(255, 8);
                    else out_g <= v_g(7 downto 0); end if;

                    if v_b > 255 then out_b <= to_unsigned(255, 8);
                    else out_b <= v_b(7 downto 0); end if;
                else
                    out_r <= in_r;
                    out_g <= in_g;
                    out_b <= in_b;
                end if;
            end if;
        end if;
    end process p_apply;

    m_tdata <= std_logic_vector(out_r) &
               std_logic_vector(out_g) &
               std_logic_vector(out_b);

end architecture rtl;
