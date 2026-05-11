-- =============================================================
-- File: gamma_lut_engine.vhd
-- Stronger visual enhancement version
-- This version increases brightness and contrast visibly.
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gamma_lut_engine is
    generic (
        IMG_WIDTH  : integer := 640;
        IMG_HEIGHT : integer := 480
    );
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;

        frame_mean  : in  unsigned(7 downto 0);
        is_dark     : in  std_logic;
        is_bright   : in  std_logic;

        s_tdata     : in  std_logic_vector(23 downto 0);
        s_tvalid    : in  std_logic;
        s_tlast     : in  std_logic;
        s_tuser     : in  std_logic;

        m_tdata     : out std_logic_vector(23 downto 0);
        m_tvalid    : out std_logic;
        m_tlast     : out std_logic;
        m_tuser     : out std_logic;

        -- Flattened LUT output (256 * 8 = 2048 bits)
        lut_r_out   : out std_logic_vector(2047 downto 0);
        lut_g_out   : out std_logic_vector(2047 downto 0);
        lut_b_out   : out std_logic_vector(2047 downto 0);
        lut_valid   : out std_logic
    );
end entity gamma_lut_engine;

architecture rtl of gamma_lut_engine is

    type lut_array_t is array (0 to 255) of integer;
    constant GAMMA_03_LUT : lut_array_t := (
          0,  48,  60,  67,  73,  78,  83,  87,  90,  94,  97,  99, 102, 104, 107, 109,
        111, 113, 115, 117, 119, 121, 122, 124, 125, 127, 129, 130, 131, 133, 134, 136,
        137, 138, 139, 141, 142, 143, 144, 145, 146, 147, 148, 149, 151, 152, 153, 154,
        155, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 164, 165, 166, 167, 168,
        168, 169, 170, 171, 172, 172, 173, 174, 174, 175, 176, 177, 177, 178, 179, 179,
        180, 181, 181, 182, 183, 183, 184, 185, 185, 186, 187, 187, 188, 188, 189, 190,
        190, 191, 191, 192, 193, 193, 194, 194, 195, 195, 196, 197, 197, 198, 198, 199,
        199, 200, 200, 201, 201, 202, 202, 203, 203, 204, 204, 205, 205, 206, 206, 207,
        207, 208, 208, 209, 209, 210, 210, 211, 211, 212, 212, 213, 213, 213, 214, 214,
        215, 215, 216, 216, 217, 217, 217, 218, 218, 219, 219, 220, 220, 220, 221, 221,
        222, 222, 223, 223, 223, 224, 224, 225, 225, 225, 226, 226, 227, 227, 227, 228,
        228, 229, 229, 229, 230, 230, 230, 231, 231, 232, 232, 232, 233, 233, 233, 234,
        234, 235, 235, 235, 236, 236, 236, 237, 237, 237, 238, 238, 238, 239, 239, 240,
        240, 240, 241, 241, 241, 242, 242, 242, 243, 243, 243, 244, 244, 244, 245, 245,
        245, 246, 246, 246, 247, 247, 247, 248, 248, 248, 249, 249, 249, 250, 250, 251,
        251, 252, 252, 252, 253, 253, 253, 253, 254, 254, 254, 255, 255, 255, 255, 255
    );

    constant GAMMA_20_LUT : lut_array_t := (
          0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   1,   1,   1,   1,
          1,   1,   1,   1,   2,   2,   2,   2,   2,   2,   3,   3,   3,   3,   4,   4,
          4,   4,   5,   5,   5,   5,   6,   6,   6,   7,   7,   7,   8,   8,   8,   9,
          9,   9,  10,  10,  11,  11,  11,  12,  12,  13,  13,  14,  14,  15,  15,  16,
         16,  17,  17,  18,  18,  19,  19,  20,  20,  21,  21,  22,  23,  23,  24,  24,
         25,  26,  26,  27,  28,  28,  29,  30,  30,  31,  32,  32,  33,  34,  35,  35,
         36,  37,  38,  38,  39,  40,  41,  42,  42,  43,  44,  45,  46,  47,  47,  48,
         49,  50,  51,  52,  53,  54,  55,  56,  56,  57,  58,  59,  60,  61,  62,  63,
         64,  65,  66,  67,  68,  69,  70,  71,  73,  74,  75,  76,  77,  78,  79,  80,
         81,  82,  84,  85,  86,  87,  88,  89,  91,  92,  93,  94,  95,  97,  98,  99,
        100, 102, 103, 104, 105, 107, 108, 109, 111, 112, 113, 115, 116, 117, 119, 120,
        121, 123, 124, 126, 127, 128, 130, 131, 133, 134, 136, 137, 139, 140, 142, 143,
        145, 146, 148, 149, 151, 152, 154, 155, 157, 158, 160, 162, 163, 165, 166, 168,
        170, 171, 173, 175, 176, 178, 180, 181, 183, 185, 186, 188, 190, 192, 193, 195,
        197, 199, 200, 202, 204, 206, 207, 209, 211, 213, 215, 217, 218, 220, 222, 224,
        226, 228, 230, 232, 233, 235, 237, 239, 241, 243, 245, 247, 249, 251, 253, 255
    );

    signal pix_r, pix_g, pix_b : unsigned(7 downto 0);
    signal out_r, out_g, out_b : unsigned(7 downto 0) := (others => '0');

    signal dly_valid, dly_last, dly_user : std_logic := '0';

begin

    -- Input splitting
    pix_r <= unsigned(s_tdata(23 downto 16));
    pix_g <= unsigned(s_tdata(15 downto 8));
    pix_b <= unsigned(s_tdata(7 downto 0));

    -- Process for intensity transformation
    process(clk, rst_n)
        variable r_i, g_i, b_i : integer range 0 to 255;
        variable r_tmp, g_tmp, b_tmp : integer;
    begin
        if rst_n = '0' then
            out_r     <= (others => '0');
            out_g     <= (others => '0');
            out_b     <= (others => '0');
            dly_valid <= '0';
            dly_last  <= '0';
            dly_user  <= '0';
        elsif rising_edge(clk) then
            dly_valid <= s_tvalid;
            dly_last  <= s_tlast;
            dly_user  <= s_tuser;

            if s_tvalid = '1' then
                r_i := to_integer(pix_r);
                g_i := to_integer(pix_g);
                b_i := to_integer(pix_b);

                if (is_dark = '1') or (frame_mean < 110) then
                    out_r <= to_unsigned(GAMMA_03_LUT(r_i), 8);
                    out_g <= to_unsigned(GAMMA_03_LUT(g_i), 8);
                    out_b <= to_unsigned(GAMMA_03_LUT(b_i), 8);
                elsif (is_bright = '1') or (frame_mean > 180) then
                    out_r <= to_unsigned(GAMMA_20_LUT(r_i), 8);
                    out_g <= to_unsigned(GAMMA_20_LUT(g_i), 8);
                    out_b <= to_unsigned(GAMMA_20_LUT(b_i), 8);
                else
                    -- Gain 1.5 linear stretch
                    r_tmp := ((r_i - 128) * 15) / 10 + 128;
                    g_tmp := ((g_i - 128) * 15) / 10 + 128;
                    b_tmp := ((b_i - 128) * 15) / 10 + 128;
                    
                    if r_tmp < 0 then r_tmp := 0; elsif r_tmp > 255 then r_tmp := 255; end if;
                    if g_tmp < 0 then g_tmp := 0; elsif g_tmp > 255 then g_tmp := 255; end if;
                    if b_tmp < 0 then b_tmp := 0; elsif b_tmp > 255 then b_tmp := 255; end if;
                    
                    out_r <= to_unsigned(r_tmp, 8);
                    out_g <= to_unsigned(g_tmp, 8);
                    out_b <= to_unsigned(b_tmp, 8);
                end if;
            end if;
        end if;
    end process;

    -- Flatten the LUT for output
    gen_lut: for i in 0 to 255 generate
        lut_r_out((i+1)*8-1 downto i*8) <= std_logic_vector(to_unsigned(GAMMA_03_LUT(i), 8));
        lut_g_out((i+1)*8-1 downto i*8) <= std_logic_vector(to_unsigned(GAMMA_03_LUT(i), 8));
        lut_b_out((i+1)*8-1 downto i*8) <= std_logic_vector(to_unsigned(GAMMA_03_LUT(i), 8));
    end generate;
    
    lut_valid <= '1';

    -- Final output
    m_tdata  <= std_logic_vector(out_r) & std_logic_vector(out_g) & std_logic_vector(out_b);
    m_tvalid <= dly_valid;
    m_tlast  <= dly_last;
    m_tuser  <= dly_user;

end architecture rtl;