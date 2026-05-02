-- =============================================================
-- File: gamma_lut_engine.vhd
-- Corrected standalone version (no external package needed)
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

        -- AXI Stream input
        s_tdata     : in  std_logic_vector(23 downto 0);
        s_tvalid    : in  std_logic;
        s_tlast     : in  std_logic;
        s_tuser     : in  std_logic;

        -- AXI Stream output
        m_tdata     : out std_logic_vector(23 downto 0);
        m_tvalid    : out std_logic;
        m_tlast     : out std_logic;
        m_tuser     : out std_logic;

        -- LUT export (flattened to avoid type problems)
        lut_r_out   : out std_logic_vector(2047 downto 0);
        lut_g_out   : out std_logic_vector(2047 downto 0);
        lut_b_out   : out std_logic_vector(2047 downto 0);
        lut_valid   : out std_logic
    );
end entity;

architecture rtl of gamma_lut_engine is

    -- =========================================================
    -- Internal LUT type (local, safe)
    -- =========================================================
    type lut_array is array (0 to 255) of unsigned(7 downto 0);

    signal lut_r : lut_array;
    signal lut_g : lut_array;
    signal lut_b : lut_array;

    -- Identity initialization
    function lut_identity return lut_array is
        variable tmp : lut_array;
    begin
        for i in 0 to 255 loop
            tmp(i) := to_unsigned(i,8);
        end loop;
        return tmp;
    end function;

    -- initialize
    signal init_done : std_logic := '0';

    -- Pixel extraction
    signal pix_r, pix_g, pix_b : unsigned(7 downto 0);

    -- Output registers
    signal out_r, out_g, out_b : unsigned(7 downto 0);

begin

    -- =========================================================
    -- LUT Initialization (identity)
    -- =========================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            lut_r <= lut_identity;
            lut_g <= lut_identity;
            lut_b <= lut_identity;
            init_done <= '0';
        elsif rising_edge(clk) then
            init_done <= '1';
        end if;
    end process;

    lut_valid <= init_done;

    -- =========================================================
    -- Pixel extraction
    -- =========================================================
    pix_r <= unsigned(s_tdata(23 downto 16));
    pix_g <= unsigned(s_tdata(15 downto 8));
    pix_b <= unsigned(s_tdata(7 downto 0));

    -- =========================================================
    -- LUT application
    -- =========================================================
    process(clk, rst_n)
        variable vr, vg, vb : unsigned(7 downto 0);
    begin
        if rst_n = '0' then
            out_r <= (others => '0');
            out_g <= (others => '0');
            out_b <= (others => '0');
        elsif rising_edge(clk) then
            if s_tvalid = '1' then

                vr := lut_r(to_integer(pix_r));
                vg := lut_g(to_integer(pix_g));
                vb := lut_b(to_integer(pix_b));

                -- Dark blending 60% enhanced
                if is_dark = '1' then
                    out_r <= resize((vr*6 + pix_r*4)/10,8);
                    out_g <= resize((vg*6 + pix_g*4)/10,8);
                    out_b <= resize((vb*6 + pix_b*4)/10,8);
                else
                    out_r <= vr;
                    out_g <= vg;
                    out_b <= vb;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================
    -- AXI output
    -- =========================================================
    m_tdata  <= std_logic_vector(out_r) &
                std_logic_vector(out_g) &
                std_logic_vector(out_b);

    m_tvalid <= s_tvalid;
    m_tlast  <= s_tlast;
    m_tuser  <= s_tuser;

    -- =========================================================
    -- Export LUT flattened (256 x 8 = 2048 bits)
    -- =========================================================
    process(lut_r, lut_g, lut_b)
    begin
        for i in 0 to 255 loop
            lut_r_out((i*8+7) downto i*8) <= std_logic_vector(lut_r(i));
            lut_g_out((i*8+7) downto i*8) <= std_logic_vector(lut_g(i));
            lut_b_out((i*8+7) downto i*8) <= std_logic_vector(lut_b(i));
        end loop;
    end process;

end architecture;