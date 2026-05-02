-- =============================================================
-- File: blend_engine.vhd
-- Description: Blend enhanced image with original.
--   blended = original*(1-strength) + enhanced*strength
--   strength is a Q0.8 fixed-point value (0=original, 255=enhanced)
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity blend_engine is
    generic (
        DATA_WIDTH : integer := 8
    );
    port (
        clk        : in  std_logic;
        rst_n      : in  std_logic;

        -- Strength Q0.8 : 0x00=0.0, 0xFF=1.0
        -- 0.35 → 89, 0.60 → 153
        strength   : in  unsigned(7 downto 0);

        -- Pixel original
        orig_data  : in  std_logic_vector(23 downto 0);
        orig_valid : in  std_logic;

        -- Pixel amélioré
        enh_data   : in  std_logic_vector(23 downto 0);
        enh_valid  : in  std_logic;

        -- Sortie
        out_data   : out std_logic_vector(23 downto 0);
        out_valid  : out std_logic
    );
end entity blend_engine;

architecture rtl of blend_engine is

    signal blend_r, blend_g, blend_b : unsigned(7 downto 0);

    signal orig_r : unsigned(7 downto 0);
    signal orig_g : unsigned(7 downto 0);
    signal orig_b : unsigned(7 downto 0);
    signal enh_r  : unsigned(7 downto 0);
    signal enh_g  : unsigned(7 downto 0);
    signal enh_b  : unsigned(7 downto 0);

    signal inv_strength : unsigned(7 downto 0);

begin

    orig_r <= unsigned(orig_data(23 downto 16));
    orig_g <= unsigned(orig_data(15 downto  8));
    orig_b <= unsigned(orig_data( 7 downto  0));

    enh_r  <= unsigned(enh_data(23 downto 16));
    enh_g  <= unsigned(enh_data(15 downto  8));
    enh_b  <= unsigned(enh_data( 7 downto  0));

    inv_strength <= 255 - strength;

    p_blend : process(clk, rst_n)
        variable sum_r, sum_g, sum_b : unsigned(15 downto 0);
    begin
        if rst_n = '0' then
            blend_r   <= (others => '0');
            blend_g   <= (others => '0');
            blend_b   <= (others => '0');
            out_valid <= '0';

        elsif rising_edge(clk) then
            out_valid <= orig_valid and enh_valid;

            if orig_valid = '1' and enh_valid = '1' then
                -- Canal R : (orig*inv_s + enh*s) / 255
                sum_r := resize(orig_r * inv_strength, 16)
                       + resize(enh_r  * strength,     16);
                blend_r <= resize(sum_r / 255, 8);

                -- Canal G
                sum_g := resize(orig_g * inv_strength, 16)
                       + resize(enh_g  * strength,     16);
                blend_g <= resize(sum_g / 255, 8);

                -- Canal B
                sum_b := resize(orig_b * inv_strength, 16)
                       + resize(enh_b  * strength,     16);
                blend_b <= resize(sum_b / 255, 8);
            end if;
        end if;
    end process p_blend;

    out_data <= std_logic_vector(blend_r) &
               std_logic_vector(blend_g) &
               std_logic_vector(blend_b);

end architecture rtl;