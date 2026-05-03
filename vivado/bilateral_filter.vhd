-- =============================================================
-- File: bilateral_filter.vhd
-- FIXED: RANGE_W_LUT now has exactly 256 entries
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

    constant RADIUS : integer := KERNEL_SIZE / 2;

    -- =========================================================
    -- Spatial Gaussian weights 5x5 (sigma_space=35)
    -- =========================================================
    type spatial_t is array(0 to 4, 0 to 4) of integer range 0 to 255;

    constant SPATIAL_W : spatial_t := (
        (150, 177, 187, 177, 150),
        (177, 210, 221, 210, 177),
        (187, 221, 232, 221, 187),
        (177, 210, 221, 210, 177),
        (150, 177, 187, 177, 150)
    );

    -- =========================================================
    -- Range weight LUT : exp(-d²/(2*35²))*255
    -- Exactly 256 entries (d=0..255)
    -- Verified count: 32 rows x 8 values = 256
    -- =========================================================
    type range_lut_t is array(0 to 255) of integer range 0 to 255;

    constant RANGE_W_LUT : range_lut_t := (
        -- d=  0..  7
        255, 255, 254, 253, 251, 248, 245, 241,
        -- d=  8.. 15
        237, 232, 226, 220, 214, 207, 200, 193,
        -- d= 16.. 23
        185, 178, 170, 162, 154, 146, 138, 130,
        -- d= 24.. 31
        123, 115, 108, 101,  94,  88,  82,  76,
        -- d= 32.. 39
         70,  65,  60,  55,  50,  46,  42,  38,
        -- d= 40.. 47
         35,  32,  29,  26,  23,  21,  19,  17,
        -- d= 48.. 55
         15,  13,  12,  10,   9,   8,   7,   6,
        -- d= 56.. 63
          5,   5,   4,   3,   3,   2,   2,   2,
        -- d= 64.. 71
          1,   1,   1,   1,   1,   0,   0,   0,
        -- d= 72.. 79
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d= 80.. 87
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d= 88.. 95
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d= 96..103
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=104..111
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=112..119
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=120..127
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=128..135
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=136..143
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=144..151
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=152..159
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=160..167
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=168..175
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=176..183
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=184..191
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=192..199
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=200..207
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=208..215
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=216..223
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=224..231
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=232..239
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=240..247
          0,   0,   0,   0,   0,   0,   0,   0,
        -- d=248..255
          0,   0,   0,   0,   0,   0,   0,   0
    );

    -- =========================================================
    -- Line buffers (4 lines for 5-row kernel)
    -- =========================================================
    type line_t is array(0 to IMG_WIDTH-1) of unsigned(7 downto 0);

    signal lb_r0, lb_r1, lb_r2, lb_r3 : line_t;
    signal lb_g0, lb_g1, lb_g2, lb_g3 : line_t;
    signal lb_b0, lb_b1, lb_b2, lb_b3 : line_t;

    signal col_cnt : integer range 0 to IMG_WIDTH-1 := 0;

    -- =========================================================
    -- Flat window signals (no 2D array)
    -- rRC = row R, col C
    -- =========================================================
    signal r00,r01,r02,r03,r04 : unsigned(7 downto 0) := (others=>'0');
    signal r10,r11,r12,r13,r14 : unsigned(7 downto 0) := (others=>'0');
    signal r20,r21,r22,r23,r24 : unsigned(7 downto 0) := (others=>'0');
    signal r30,r31,r32,r33,r34 : unsigned(7 downto 0) := (others=>'0');
    signal r40,r41,r42,r43,r44 : unsigned(7 downto 0) := (others=>'0');

    signal g00,g01,g02,g03,g04 : unsigned(7 downto 0) := (others=>'0');
    signal g10,g11,g12,g13,g14 : unsigned(7 downto 0) := (others=>'0');
    signal g20,g21,g22,g23,g24 : unsigned(7 downto 0) := (others=>'0');
    signal g30,g31,g32,g33,g34 : unsigned(7 downto 0) := (others=>'0');
    signal g40,g41,g42,g43,g44 : unsigned(7 downto 0) := (others=>'0');

    signal b00,b01,b02,b03,b04 : unsigned(7 downto 0) := (others=>'0');
    signal b10,b11,b12,b13,b14 : unsigned(7 downto 0) := (others=>'0');
    signal b20,b21,b22,b23,b24 : unsigned(7 downto 0) := (others=>'0');
    signal b30,b31,b32,b33,b34 : unsigned(7 downto 0) := (others=>'0');
    signal b40,b41,b42,b43,b44 : unsigned(7 downto 0) := (others=>'0');

    -- Current pixel
    signal cur_r, cur_g, cur_b : unsigned(7 downto 0);

    -- Pipeline
    signal pipe_valid : std_logic := '0';
    signal pipe_last  : std_logic := '0';
    signal pipe_user  : std_logic := '0';
    signal pipe_data  : std_logic_vector(23 downto 0) := (others=>'0');

    -- Filter output
    signal filt_r, filt_g, filt_b : unsigned(7 downto 0) := (others=>'0');

begin

    cur_r <= unsigned(s_tdata(23 downto 16));
    cur_g <= unsigned(s_tdata(15 downto  8));
    cur_b <= unsigned(s_tdata( 7 downto  0));

    -- =========================================================
    -- Line buffer + window update
    -- =========================================================
    p_buf : process(clk, rst_n)
    begin
        if rst_n = '0' then
            col_cnt    <= 0;
            pipe_valid <= '0';
            pipe_last  <= '0';
            pipe_user  <= '0';

        elsif rising_edge(clk) then

            pipe_valid <= s_tvalid;
            pipe_last  <= s_tlast;
            pipe_user  <= s_tuser;
            pipe_data  <= s_tdata;

            if s_tvalid = '1' then

                -- Shift line buffers vertically
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

                -- Shift window horizontally
                r00<=r01; r01<=r02; r02<=r03; r03<=r04;
                r10<=r11; r11<=r12; r12<=r13; r13<=r14;
                r20<=r21; r21<=r22; r22<=r23; r23<=r24;
                r30<=r31; r31<=r32; r32<=r33; r33<=r34;
                r40<=r41; r41<=r42; r42<=r43; r43<=r44;

                g00<=g01; g01<=g02; g02<=g03; g03<=g04;
                g10<=g11; g11<=g12; g12<=g13; g13<=g14;
                g20<=g21; g21<=g22; g22<=g23; g23<=g24;
                g30<=g31; g31<=g32; g32<=g33; g33<=g34;
                g40<=g41; g41<=g42; g42<=g43; g43<=g44;

                b00<=b01; b01<=b02; b02<=b03; b03<=b04;
                b10<=b11; b11<=b12; b12<=b13; b13<=b14;
                b20<=b21; b21<=b22; b22<=b23; b23<=b24;
                b30<=b31; b31<=b32; b32<=b33; b33<=b34;
                b40<=b41; b41<=b42; b42<=b43; b43<=b44;

                -- Insert new rightmost column
                r04 <= lb_r3(col_cnt);
                r14 <= lb_r2(col_cnt);
                r24 <= lb_r1(col_cnt);
                r34 <= lb_r0(col_cnt);
                r44 <= cur_r;

                g04 <= lb_g3(col_cnt);
                g14 <= lb_g2(col_cnt);
                g24 <= lb_g1(col_cnt);
                g34 <= lb_g0(col_cnt);
                g44 <= cur_g;

                b04 <= lb_b3(col_cnt);
                b14 <= lb_b2(col_cnt);
                b24 <= lb_b1(col_cnt);
                b34 <= lb_b0(col_cnt);
                b44 <= cur_b;

                if col_cnt = IMG_WIDTH-1 then
                    col_cnt <= 0;
                else
                    col_cnt <= col_cnt + 1;
                end if;
            end if;
        end if;
    end process p_buf;

    -- =========================================================
    -- Bilateral filter computation
    -- =========================================================
    p_filter : process(clk, rst_n)

        variable ctr_r, ctr_g, ctr_b : integer range 0 to 255;
        variable pv_r,  pv_g,  pv_b  : integer range 0 to 255;
        variable dr, dg, db           : integer range 0 to 255;
        variable wr, wg, wb, ws       : integer range 0 to 255;
        variable wtr, wtg, wtb        : integer range 0 to 65025;

        variable sum_wr, sum_wg, sum_wb   : integer;
        variable sum_fr, sum_fg, sum_fb   : integer;
        variable res_r, res_g, res_b      : integer;

    begin
        if rst_n = '0' then
            filt_r <= (others => '0');
            filt_g <= (others => '0');
            filt_b <= (others => '0');

        elsif rising_edge(clk) then
            if pipe_valid = '1' then

                -- Center pixel
                ctr_r := to_integer(r22);
                ctr_g := to_integer(g22);
                ctr_b := to_integer(b22);

                sum_wr := 0; sum_wg := 0; sum_wb := 0;
                sum_fr := 0; sum_fg := 0; sum_fb := 0;

                -- Row 0
                -- col 0
                pv_r:=to_integer(r00); pv_g:=to_integer(g00); pv_b:=to_integer(b00);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=150; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 1
                pv_r:=to_integer(r01); pv_g:=to_integer(g01); pv_b:=to_integer(b01);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=177; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 2
                pv_r:=to_integer(r02); pv_g:=to_integer(g02); pv_b:=to_integer(b02);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=187; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 3
                pv_r:=to_integer(r03); pv_g:=to_integer(g03); pv_b:=to_integer(b03);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=177; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 4
                pv_r:=to_integer(r04); pv_g:=to_integer(g04); pv_b:=to_integer(b04);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=150; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- Row 1
                -- col 0
                pv_r:=to_integer(r10); pv_g:=to_integer(g10); pv_b:=to_integer(b10);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=177; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 1
                pv_r:=to_integer(r11); pv_g:=to_integer(g11); pv_b:=to_integer(b11);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=210; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 2
                pv_r:=to_integer(r12); pv_g:=to_integer(g12); pv_b:=to_integer(b12);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=221; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 3
                pv_r:=to_integer(r13); pv_g:=to_integer(g13); pv_b:=to_integer(b13);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=210; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 4
                pv_r:=to_integer(r14); pv_g:=to_integer(g14); pv_b:=to_integer(b14);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=177; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- Row 2
                -- col 0
                pv_r:=to_integer(r20); pv_g:=to_integer(g20); pv_b:=to_integer(b20);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=187; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 1
                pv_r:=to_integer(r21); pv_g:=to_integer(g21); pv_b:=to_integer(b21);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=221; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 2 (center)
                pv_r:=ctr_r; pv_g:=ctr_g; pv_b:=ctr_b;
                dr:=0; dg:=0; db:=0;
                ws:=232; wr:=255; wg:=255; wb:=255;
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 3
                pv_r:=to_integer(r23); pv_g:=to_integer(g23); pv_b:=to_integer(b23);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=221; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 4
                pv_r:=to_integer(r24); pv_g:=to_integer(g24); pv_b:=to_integer(b24);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=187; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- Row 3
                -- col 0
                pv_r:=to_integer(r30); pv_g:=to_integer(g30); pv_b:=to_integer(b30);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=177; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 1
                pv_r:=to_integer(r31); pv_g:=to_integer(g31); pv_b:=to_integer(b31);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=210; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 2
                pv_r:=to_integer(r32); pv_g:=to_integer(g32); pv_b:=to_integer(b32);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=221; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 3
                pv_r:=to_integer(r33); pv_g:=to_integer(g33); pv_b:=to_integer(b33);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=210; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 4
                pv_r:=to_integer(r34); pv_g:=to_integer(g34); pv_b:=to_integer(b34);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=177; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- Row 4
                -- col 0
                pv_r:=to_integer(r40); pv_g:=to_integer(g40); pv_b:=to_integer(b40);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=150; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 1
                pv_r:=to_integer(r41); pv_g:=to_integer(g41); pv_b:=to_integer(b41);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=177; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 2
                pv_r:=to_integer(r42); pv_g:=to_integer(g42); pv_b:=to_integer(b42);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=187; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 3
                pv_r:=to_integer(r43); pv_g:=to_integer(g43); pv_b:=to_integer(b43);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=177; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- col 4
                pv_r:=to_integer(r44); pv_g:=to_integer(g44); pv_b:=to_integer(b44);
                if pv_r>=ctr_r then dr:=pv_r-ctr_r; else dr:=ctr_r-pv_r; end if;
                if pv_g>=ctr_g then dg:=pv_g-ctr_g; else dg:=ctr_g-pv_g; end if;
                if pv_b>=ctr_b then db:=pv_b-ctr_b; else db:=ctr_b-pv_b; end if;
                ws:=150; wr:=RANGE_W_LUT(dr); wg:=RANGE_W_LUT(dg); wb:=RANGE_W_LUT(db);
                wtr:=(ws*wr)/255; wtg:=(ws*wg)/255; wtb:=(ws*wb)/255;
                sum_wr:=sum_wr+wtr; sum_fr:=sum_fr+pv_r*wtr;
                sum_wg:=sum_wg+wtg; sum_fg:=sum_fg+pv_g*wtg;
                sum_wb:=sum_wb+wtb; sum_fb:=sum_fb+pv_b*wtb;

                -- Final division
                if sum_wr > 0 then res_r := sum_fr/sum_wr;
                else res_r := ctr_r; end if;
                if sum_wg > 0 then res_g := sum_fg/sum_wg;
                else res_g := ctr_g; end if;
                if sum_wb > 0 then res_b := sum_fb/sum_wb;
                else res_b := ctr_b; end if;

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
    -- Output
    -- =========================================================
    m_tdata  <= std_logic_vector(filt_r) &
                std_logic_vector(filt_g) &
                std_logic_vector(filt_b) when enable='1'
                else pipe_data;
    m_tvalid <= pipe_valid;
    m_tlast  <= pipe_last;
    m_tuser  <= pipe_user;

end architecture rtl;