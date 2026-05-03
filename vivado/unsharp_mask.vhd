library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity unsharp_mask is
    generic (
        IMG_WIDTH  : integer := 640;
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
end entity unsharp_mask;

architecture rtl of unsharp_mask is

    signal out_r : unsigned(7 downto 0) := (others => '0');
    signal out_g : unsigned(7 downto 0) := (others => '0');
    signal out_b : unsigned(7 downto 0) := (others => '0');

begin

    m_tdata  <= std_logic_vector(out_r) &
                std_logic_vector(out_g) &
                std_logic_vector(out_b);

    m_tvalid <= s_tvalid;
    m_tlast  <= s_tlast;
    m_tuser  <= s_tuser;

    process(clk, rst_n)
        variable r_i, g_i, b_i : integer;
    begin
        if rst_n = '0' then
            out_r <= (others => '0');
            out_g <= (others => '0');
            out_b <= (others => '0');

        elsif rising_edge(clk) then
            if s_tvalid = '1' then
                r_i := to_integer(unsigned(s_tdata(23 downto 16)));
                g_i := to_integer(unsigned(s_tdata(15 downto 8)));
                b_i := to_integer(unsigned(s_tdata(7 downto 0)));

                if enable = '1' then
                    -- Gentle enhancement only
                    if r_i < 96 then
                        r_i := (r_i * 106) / 100 + 2;
                    elsif r_i > 200 then
                        r_i := (r_i * 98) / 100;
                    else
                        r_i := ((r_i - 128) * 108) / 100 + 128;
                    end if;

                    if g_i < 96 then
                        g_i := (g_i * 106) / 100 + 2;
                    elsif g_i > 200 then
                        g_i := (g_i * 98) / 100;
                    else
                        g_i := ((g_i - 128) * 108) / 100 + 128;
                    end if;

                    if b_i < 96 then
                        b_i := (b_i * 106) / 100 + 2;
                    elsif b_i > 200 then
                        b_i := (b_i * 98) / 100;
                    else
                        b_i := ((b_i - 128) * 108) / 100 + 128;
                    end if;
                end if;

                -- Clamp
                if r_i < 0 then
                    r_i := 0;
                elsif r_i > 255 then
                    r_i := 255;
                end if;

                if g_i < 0 then
                    g_i := 0;
                elsif g_i > 255 then
                    g_i := 255;
                end if;

                if b_i < 0 then
                    b_i := 0;
                elsif b_i > 255 then
                    b_i := 255;
                end if;

                out_r <= to_unsigned(r_i, 8);
                out_g <= to_unsigned(g_i, 8);
                out_b <= to_unsigned(b_i, 8);
            end if;
        end if;
    end process;

end architecture rtl;