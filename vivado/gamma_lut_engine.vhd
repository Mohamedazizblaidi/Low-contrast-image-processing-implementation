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

        -- Kept only for compatibility with agcwd_top
        lut_r_out   : out std_logic_vector(2047 downto 0);
        lut_g_out   : out std_logic_vector(2047 downto 0);
        lut_b_out   : out std_logic_vector(2047 downto 0);
        lut_valid   : out std_logic
    );
end entity gamma_lut_engine;

architecture rtl of gamma_lut_engine is

    signal pix_r : unsigned(7 downto 0);
    signal pix_g : unsigned(7 downto 0);
    signal pix_b : unsigned(7 downto 0);

    signal out_r : unsigned(7 downto 0) := (others => '0');
    signal out_g : unsigned(7 downto 0) := (others => '0');
    signal out_b : unsigned(7 downto 0) := (others => '0');

begin

    pix_r <= unsigned(s_tdata(23 downto 16));
    pix_g <= unsigned(s_tdata(15 downto 8));
    pix_b <= unsigned(s_tdata(7 downto 0));

    -- Output stream
    m_tdata  <= std_logic_vector(out_r) &
                std_logic_vector(out_g) &
                std_logic_vector(out_b);
    m_tvalid <= s_tvalid;
    m_tlast  <= s_tlast;
    m_tuser  <= s_tuser;

    -- Dummy LUT outputs for compatibility
    lut_r_out <= (others => '0');
    lut_g_out <= (others => '0');
    lut_b_out <= (others => '0');
    lut_valid <= '1';

    process(clk, rst_n)
        variable r_i, g_i, b_i : integer;
    begin
        if rst_n = '0' then
            out_r <= (others => '0');
            out_g <= (others => '0');
            out_b <= (others => '0');

        elsif rising_edge(clk) then
            if s_tvalid = '1' then
                r_i := to_integer(pix_r);
                g_i := to_integer(pix_g);
                b_i := to_integer(pix_b);

                -- Strong boost for dark images
                if (is_dark = '1') or (frame_mean < to_unsigned(110, 8)) then
                    r_i := (r_i * 14) / 10 + 20;
                    g_i := (g_i * 14) / 10 + 20;
                    b_i := (b_i * 14) / 10 + 20;

                -- Mild compression for very bright images
                elsif (is_bright = '1') or (frame_mean > to_unsigned(180, 8)) then
                    r_i := (r_i * 95) / 100;
                    g_i := (g_i * 95) / 100;
                    b_i := (b_i * 95) / 100;

                -- Normal contrast boost
                else
                    r_i := ((r_i - 128) * 12) / 10 + 128;
                    g_i := ((g_i - 128) * 12) / 10 + 128;
                    b_i := ((b_i - 128) * 12) / 10 + 128;
                end if;

                -- Clamp to [0,255]
                if r_i < 0 then r_i := 0; end if;
                if g_i < 0 then g_i := 0; end if;
                if b_i < 0 then b_i := 0; end if;

                if r_i > 255 then r_i := 255; end if;
                if g_i > 255 then g_i := 255; end if;
                if b_i > 255 then b_i := 255; end if;

                out_r <= to_unsigned(r_i, 8);
                out_g <= to_unsigned(g_i, 8);
                out_b <= to_unsigned(b_i, 8);
            end if;
        end if;
    end process;

end architecture rtl;