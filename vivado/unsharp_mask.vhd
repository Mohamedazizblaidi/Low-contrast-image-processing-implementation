-- =============================================================
-- File: unsharp_mask.vhd
-- NO 2D arrays at all - guaranteed to compile
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
        clk      : in  std_logic;
        rst_n    : in  std_logic;
        enable   : in  std_logic;

        s_tdata  : in  std_logic_vector(23 downto 0);
        s_tvalid : in  std_logic;
        s_tlast  : in  std_logic;
        s_tuser  : in  std_logic;

        m_tdata  : out std_logic_vector(23 downto 0);
        m_tvalid : out std_logic;
        m_tlast  : out std_logic;
        m_tuser  : out std_logic
    );
end entity unsharp_mask;

architecture rtl of unsharp_mask is

    -- =========================================================
    -- Line buffer type (1D only)
    -- =========================================================
    type line_t is array(0 to IMG_WIDTH-1) of unsigned(7 downto 0);

    -- 4 line buffers per channel (for 5 rows total)
    signal lb_r0, lb_r1, lb_r2, lb_r3 : line_t;
    signal lb_g0, lb_g1, lb_g2, lb_g3 : line_t;
    signal lb_b0, lb_b1, lb_b2, lb_b3 : line_t;

    -- =========================================================
    -- Window pixels - fully flat, no 2D array at all
    -- Row 0 = oldest, Row 4 = current
    -- =========================================================

    -- Row 0
    signal r00,r01,r02,r03,r04 : unsigned(7 downto 0);
    signal g00,g01,g02,g03,g04 : unsigned(7 downto 0);
    signal b00,b01,b02,b03,b04 : unsigned(7 downto 0);

    -- Row 1
    signal r10,r11,r12,r13,r14 : unsigned(7 downto 0);
    signal g10,g11,g12,g13,g14 : unsigned(7 downto 0);
    signal b10,b11,b12,b13,b14 : unsigned(7 downto 0);

    -- Row 2
    signal r20,r21,r22,r23,r24 : unsigned(7 downto 0);
    signal g20,g21,g22,g23,g24 : unsigned(7 downto 0);
    signal b20,b21,b22,b23,b24 : unsigned(7 downto 0);

    -- Row 3
    signal r30,r31,r32,r33,r34 : unsigned(7 downto 0);
    signal g30,g31,g32,g33,g34 : unsigned(7 downto 0);
    signal b30,b31,b32,b33,b34 : unsigned(7 downto 0);

    -- Row 4 (current row)
    signal r40,r41,r42,r43,r44 : unsigned(7 downto 0);
    signal g40,g41,g42,g43,g44 : unsigned(7 downto 0);
    signal b40,b41,b42,b43,b44 : unsigned(7 downto 0);

    -- =========================================================
    -- Column counter
    -- =========================================================
    signal col_cnt : integer range 0 to IMG_WIDTH-1 := 0;

    -- =========================================================
    -- Current pixel channels
    -- =========================================================
    signal cur_r : unsigned(7 downto 0);
    signal cur_g : unsigned(7 downto 0);
    signal cur_b : unsigned(7 downto 0);

    -- =========================================================
    -- Pipeline delay
    -- =========================================================
    signal dly_valid : std_logic := '0';
    signal dly_last  : std_logic := '0';
    signal dly_user  : std_logic := '0';
    signal dly_data  : std_logic_vector(23 downto 0) := (others=>'0');

    -- =========================================================
    -- Output
    -- =========================================================
    signal sharp_r : unsigned(7 downto 0) := (others=>'0');
    signal sharp_g : unsigned(7 downto 0) := (others=>'0');
    signal sharp_b : unsigned(7 downto 0) := (others=>'0');

begin

    cur_r <= unsigned(s_tdata(23 downto 16));
    cur_g <= unsigned(s_tdata(15 downto 8));
    cur_b <= unsigned(s_tdata(7 downto 0));

    -- =========================================================
    -- Process 1 : Line buffers + sliding window (flat signals)
    -- =========================================================
    p_window : process(clk, rst_n)
    begin
        if rst_n = '0' then
            col_cnt   <= 0;
            dly_valid <= '0';
            dly_last  <= '0';
            dly_user  <= '0';

        elsif rising_edge(clk) then

            dly_valid <= s_tvalid;
            dly_last  <= s_tlast;
            dly_user  <= s_tuser;
            dly_data  <= s_tdata;

            if s_tvalid = '1' then

                -- Save to line buffers (shift down)
                lb_r3(col_cnt) <= lb_r2(col_cnt);
                lb_r2(col_cnt) <= lb_r1(col_cnt);
                lb_r1(col_cnt) <= lb_r0(col_cnt);
                lb_r0(col_cnt) <= cur_r;

                lb_g3(col_cnt) <= lb_g2(col_cnt);
                lb_g2(col_cnt) <= lb_g1(col_cnt);
                lb_g1(col_cnt) <= lb_g0(col_cnt);
                lb_g0(col_cnt) <= cur_g;

                lb_b3(col_cnt) <= lb_b2(col_cnt);
                lb_b2(col_cnt) <= lb_b1(col_cnt);
                lb_b1(col_cnt) <= lb_b0(col_cnt);
                lb_b0(col_cnt) <= cur_b;

                -- =============================================
                -- Shift window columns LEFT (col 0 = oldest)
                -- =============================================

                -- Row 0 (oldest line = lb_r3)
                r00 <= r01; r01 <= r02; r02 <= r03; r03 <= r04;
                g00 <= g01; g01 <= g02; g02 <= g03; g03 <= g04;
                b00 <= b01; b01 <= b02; b02 <= b03; b03 <= b04;

                -- Row 1
                r10 <= r11; r11 <= r12; r12 <= r13; r13 <= r14;
                g10 <= g11; g11 <= g12; g12 <= g13; g13 <= g14;
                b10 <= b11; b11 <= b12; b12 <= b13; b13 <= b14;

                -- Row 2
                r20 <= r21; r21 <= r22; r22 <= r23; r23 <= r24;
                g20 <= g21; g21 <= g22; g22 <= g23; g23 <= g24;
                b20 <= b21; b21 <= b22; b22 <= b23; b23 <= b24;

                -- Row 3
                r30 <= r31; r31 <= r32; r32 <= r33; r33 <= r34;
                g30 <= g31; g31 <= g32; g32 <= g33; g33 <= g34;
                b30 <= b31; b31 <= b32; b32 <= b33; b33 <= b34;

                -- Row 4 (current row)
                r40 <= r41; r41 <= r42; r42 <= r43; r43 <= r44;
                g40 <= g41; g41 <= g42; g42 <= g43; g43 <= g44;
                b40 <= b41; b41 <= b42; b42 <= b43; b43 <= b44;

                -- =============================================
                -- Insert rightmost column (col index 4)
                -- =============================================
                r04 <= lb_r3(col_cnt);
                g04 <= lb_g3(col_cnt);
                b04 <= lb_b3(col_cnt);

                r14 <= lb_r2(col_cnt);
                g14 <= lb_g2(col_cnt);
                b14 <= lb_b2(col_cnt);

                r24 <= lb_r1(col_cnt);
                g24 <= lb_g1(col_cnt);
                b24 <= lb_b1(col_cnt);

                r34 <= lb_r0(col_cnt);
                g34 <= lb_g0(col_cnt);
                b34 <= lb_b0(col_cnt);

                r44 <= cur_r;
                g44 <= cur_g;
                b44 <= cur_b;

                -- Column counter
                if col_cnt = IMG_WIDTH - 1 then
                    col_cnt <= 0;
                else
                    col_cnt <= col_cnt + 1;
                end if;

            end if;
        end if;
    end process p_window;

    -- =========================================================
    -- Process 2 : Gaussian blur + unsharp mask
    -- Kernel 5x5 sigma=2 (integer approximation, sum=200)
    -- sharpened = (14*orig - 4*blur) / 10
    -- =========================================================
    p_sharp : process(clk, rst_n)

        variable blur_r, blur_g, blur_b : integer;
        variable orig_r, orig_g, orig_b : integer;
        variable res_r,  res_g,  res_b  : integer;

    begin
        if rst_n = '0' then
            sharp_r <= (others => '0');
            sharp_g <= (others => '0');
            sharp_b <= (others => '0');

        elsif rising_edge(clk) then

            if dly_valid = '1' then

                -- Gauss sum: coefficients x pixel values
                -- Kernel:
                --  4  6  7  6  4
                --  6  9 10  9  6
                --  7 10 12 10  7
                --  6  9 10  9  6
                --  4  6  7  6  4
                -- Sum = 200

                blur_r :=
                    4*to_integer(r00) + 6*to_integer(r01) +
                    7*to_integer(r02) + 6*to_integer(r03) +
                    4*to_integer(r04) +

                    6*to_integer(r10) + 9*to_integer(r11) +
                   10*to_integer(r12) + 9*to_integer(r13) +
                    6*to_integer(r14) +

                    7*to_integer(r20) +10*to_integer(r21) +
                   12*to_integer(r22) +10*to_integer(r23) +
                    7*to_integer(r24) +

                    6*to_integer(r30) + 9*to_integer(r31) +
                   10*to_integer(r32) + 9*to_integer(r33) +
                    6*to_integer(r34) +

                    4*to_integer(r40) + 6*to_integer(r41) +
                    7*to_integer(r42) + 6*to_integer(r43) +
                    4*to_integer(r44);

                blur_g :=
                    4*to_integer(g00) + 6*to_integer(g01) +
                    7*to_integer(g02) + 6*to_integer(g03) +
                    4*to_integer(g04) +

                    6*to_integer(g10) + 9*to_integer(g11) +
                   10*to_integer(g12) + 9*to_integer(g13) +
                    6*to_integer(g14) +

                    7*to_integer(g20) +10*to_integer(g21) +
                   12*to_integer(g22) +10*to_integer(g23) +
                    7*to_integer(g24) +

                    6*to_integer(g30) + 9*to_integer(g31) +
                   10*to_integer(g32) + 9*to_integer(g33) +
                    6*to_integer(g34) +

                    4*to_integer(g40) + 6*to_integer(g41) +
                    7*to_integer(g42) + 6*to_integer(g43) +
                    4*to_integer(g44);

                blur_b :=
                    4*to_integer(b00) + 6*to_integer(b01) +
                    7*to_integer(b02) + 6*to_integer(b03) +
                    4*to_integer(b04) +

                    6*to_integer(b10) + 9*to_integer(b11) +
                   10*to_integer(b12) + 9*to_integer(b13) +
                    6*to_integer(b14) +

                    7*to_integer(b20) +10*to_integer(b21) +
                   12*to_integer(b22) +10*to_integer(b23) +
                    7*to_integer(b24) +

                    6*to_integer(b30) + 9*to_integer(b31) +
                   10*to_integer(b32) + 9*to_integer(b33) +
                    6*to_integer(b34) +

                    4*to_integer(b40) + 6*to_integer(b41) +
                    7*to_integer(b42) + 6*to_integer(b43) +
                    4*to_integer(b44);

                blur_r := blur_r / 200;
                blur_g := blur_g / 200;
                blur_b := blur_b / 200;

                -- Original pixel (delayed)
                orig_r := to_integer(unsigned(dly_data(23 downto 16)));
                orig_g := to_integer(unsigned(dly_data(15 downto 8)));
                orig_b := to_integer(unsigned(dly_data(7 downto 0)));

                -- Unsharp: 1.4*orig - 0.4*blur
                res_r := (14*orig_r - 4*blur_r) / 10;
                res_g := (14*orig_g - 4*blur_g) / 10;
                res_b := (14*orig_b - 4*blur_b) / 10;

                -- Clamp
                if res_r < 0   then res_r := 0;   end if;
                if res_r > 255 then res_r := 255; end if;
                if res_g < 0   then res_g := 0;   end if;
                if res_g > 255 then res_g := 255; end if;
                if res_b < 0   then res_b := 0;   end if;
                if res_b > 255 then res_b := 255; end if;

                sharp_r <= to_unsigned(res_r, 8);
                sharp_g <= to_unsigned(res_g, 8);
                sharp_b <= to_unsigned(res_b, 8);

            end if;
        end if;
    end process p_sharp;

    -- =========================================================
    -- Output mux
    -- =========================================================
    m_tdata  <= std_logic_vector(sharp_r) &
                std_logic_vector(sharp_g) &
                std_logic_vector(sharp_b) when enable = '1'
                else dly_data;

    m_tvalid <= dly_valid;
    m_tlast  <= dly_last;
    m_tuser  <= dly_user;

end architecture rtl;