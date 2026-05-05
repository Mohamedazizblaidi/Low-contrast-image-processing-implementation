-- =============================================================
-- File: histogram_engine.vhd
-- Description: Compute 256-bin histogram for one uint8 channel
--              Uses Block RAM for the histogram bins
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity histogram_engine is
    generic (
        IMG_WIDTH  : integer := 640;
        IMG_HEIGHT : integer := 480;
        DATA_WIDTH : integer := 8   -- 256 bins
    );
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic;

        -- Entrée canal pixel
        pixel_in    : in  unsigned(DATA_WIDTH-1 downto 0);
        pix_valid   : in  std_logic;
        frame_start : in  std_logic;
        frame_end   : in  std_logic;

        -- Lecture histogramme (après frame_done)
        rd_addr     : in  unsigned(DATA_WIDTH-1 downto 0);
        rd_data     : out unsigned(19 downto 0); -- Max pixels = 640*480 = 307200
        hist_done   : out std_logic
    );
end entity histogram_engine;

architecture rtl of histogram_engine is

    -- BRAM pour histogramme : 256 bins x 20 bits
    type hist_ram_t is array (0 to 255) of unsigned(19 downto 0);
    signal hist_ram   : hist_ram_t := (others => (others => '0'));

    signal hist_done_reg : std_logic := '0';

    -- Pipeline d'écriture (read-modify-write en 2 cycles)
    signal pipe_addr  : unsigned(DATA_WIDTH-1 downto 0);
    signal pipe_valid : std_logic := '0';
    signal pipe_data  : unsigned(19 downto 0);

begin

    -- =========================================================
    -- Process : Incrémentation histogramme avec pipeline RMW
    -- =========================================================
    p_hist : process(clk, rst_n)
    begin
        if rst_n = '0' then
            hist_ram      <= (others => (others => '0'));
            hist_done_reg <= '0';
            pipe_valid    <= '0';

        elsif rising_edge(clk) then
            hist_done_reg <= '0';

            -- Remise à zéro en début de frame
            if frame_start = '1' then
                hist_ram   <= (others => (others => '0'));
                pipe_valid <= '0';
            end if;

            -- Étage 1 : lecture de la valeur courante
            pipe_addr  <= pixel_in;
            pipe_valid <= pix_valid;
            if pix_valid = '1' then
                pipe_data <= hist_ram(to_integer(pixel_in));
            end if;

            -- Étage 2 : incrémentation et écriture
            if pipe_valid = '1' then
                hist_ram(to_integer(pipe_addr)) <= pipe_data + 1;
            end if;

            -- Fin de frame
            if frame_end = '1' and pix_valid = '1' then
                hist_done_reg <= '1';
            end if;
        end if;
    end process p_hist;

    -- =========================================================
    -- Lecture asynchrone de l'histogramme
    -- =========================================================
    rd_data   <= hist_ram(to_integer(rd_addr));
    hist_done <= hist_done_reg;

end architecture rtl;