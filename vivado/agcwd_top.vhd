-- =============================================================
-- File: agcwd_top.vhd
-- Description: Top-level module for AGCWD RGB image enhancement
-- Target: Xilinx Artix-7 / Zynq-7000
-- Clock: 100 MHz
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity agcwd_top is
    generic (
        IMG_WIDTH       : integer := 640;
        IMG_HEIGHT      : integer := 480;
        DATA_WIDTH      : integer := 8;    -- Bits per channel
        ALPHA_FRAC_BITS : integer := 8;    -- Fixed-point fractional bits
        -- Alpha = 0.5 => 0x80 en Q0.8
        ALPHA_VALUE     : integer := 128
    );
    port (
        -- Clock & Reset
        clk             : in  std_logic;
        rst_n           : in  std_logic;

        -- Input pixel stream (AXI4-Stream)
        s_axis_tdata    : in  std_logic_vector(23 downto 0); -- R[23:16] G[15:8] B[7:0]
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;   -- Fin de ligne
        s_axis_tuser    : in  std_logic;   -- Start of Frame

        -- Output pixel stream (AXI4-Stream)
        m_axis_tdata    : out std_logic_vector(23 downto 0);
        m_axis_tvalid   : out std_logic;
        m_axis_tready   : in  std_logic;
        m_axis_tlast    : out std_logic;
        m_axis_tuser    : out std_logic;

        -- Control
        enable_denoise  : in  std_logic;
        enable_sharpen  : in  std_logic;
        enable_balance  : in  std_logic;

        -- Status
        frame_done      : out std_logic;
        frame_dark      : out std_logic;
        frame_bright    : out std_logic
    );
end entity agcwd_top;

architecture rtl of agcwd_top is

    -- =========================================================
    -- Signaux internes entre étages pipeline
    -- =========================================================

    -- Étage 0 → 1 : Après détection statistiques
    signal stage0_data   : std_logic_vector(23 downto 0);
    signal stage0_valid  : std_logic;
    signal stage0_last   : std_logic;
    signal stage0_user   : std_logic;

    -- Étage 1 → 2 : Après bilateral filter
    signal stage1_data   : std_logic_vector(23 downto 0);
    signal stage1_valid  : std_logic;
    signal stage1_last   : std_logic;
    signal stage1_user   : std_logic;

    -- Étage 2 → 3 : Après AGCWD core
    signal stage2_data   : std_logic_vector(23 downto 0);
    signal stage2_valid  : std_logic;
    signal stage2_last   : std_logic;
    signal stage2_user   : std_logic;

    -- Étage 3 → 4 : Après gray-world balance
    signal stage3_data   : std_logic_vector(23 downto 0);
    signal stage3_valid  : std_logic;
    signal stage3_last   : std_logic;
    signal stage3_user   : std_logic;

    -- Étage 4 → sortie : Après unsharp mask
    signal stage4_data   : std_logic_vector(23 downto 0);
    signal stage4_valid  : std_logic;
    signal stage4_last   : std_logic;
    signal stage4_user   : std_logic;

    -- Statistiques globales de la frame
    signal frame_mean    : unsigned(7 downto 0);
    signal frame_std     : unsigned(7 downto 0);
    signal is_dark       : std_logic;
    signal is_bright     : std_logic;
    signal stats_ready   : std_logic;

    -- LUT Gamma partagée (256 entrées x 8 bits par canal)
    type lut_array is array (0 to 255) of unsigned(7 downto 0);
    signal gamma_lut_r   : lut_array;
    signal gamma_lut_g   : lut_array;
    signal gamma_lut_b   : lut_array;
    signal lut_valid     : std_logic;

begin

    -- =========================================================
    -- ÉTAGE 0 : Statistiques frame (passe 1)
    -- =========================================================
    u_stats : entity work.channel_stats
        generic map (
            IMG_WIDTH   => IMG_WIDTH,
            IMG_HEIGHT  => IMG_HEIGHT,
            DATA_WIDTH  => DATA_WIDTH
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            pixel_in    => s_axis_tdata,
            pix_valid   => s_axis_tvalid,
            frame_start => s_axis_tuser,
            frame_end   => s_axis_tlast,
            mean_out    => frame_mean,
            std_out     => frame_std,
            is_dark     => is_dark,
            is_bright   => is_bright,
            stats_done  => stats_ready
        );

    -- Bypass direct pour le premier étage
    stage0_data  <= s_axis_tdata;
    stage0_valid <= s_axis_tvalid;
    stage0_last  <= s_axis_tlast;
    stage0_user  <= s_axis_tuser;
    s_axis_tready <= '1'; -- Simplification : toujours prêt

    -- =========================================================
    -- ÉTAGE 1 : Bilateral Filter (optionnel)
    -- =========================================================
    u_bilateral : entity work.bilateral_filter
        generic map (
            IMG_WIDTH  => IMG_WIDTH,
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk        => clk,
            rst_n      => rst_n,
            enable     => enable_denoise,
            -- Entrée
            s_tdata    => stage0_data,
            s_tvalid   => stage0_valid,
            s_tlast    => stage0_last,
            s_tuser    => stage0_user,
            -- Sortie
            m_tdata    => stage1_data,
            m_tvalid   => stage1_valid,
            m_tlast    => stage1_last,
            m_tuser    => stage1_user
        );

    -- =========================================================
    -- ÉTAGE 2 : AGCWD Core (Histogram + PDF + CDF + LUT)
    -- =========================================================
    u_agcwd_core : entity work.gamma_lut_engine
        generic map (
            IMG_WIDTH       => IMG_WIDTH,
            IMG_HEIGHT      => IMG_HEIGHT,
            DATA_WIDTH      => DATA_WIDTH,
            ALPHA_FRAC_BITS => ALPHA_FRAC_BITS,
            ALPHA_VALUE     => ALPHA_VALUE
        )
        port map (
            clk           => clk,
            rst_n         => rst_n,
            -- Statistiques
            frame_mean    => frame_mean,
            is_dark       => is_dark,
            is_bright     => is_bright,
            -- Entrée
            s_tdata       => stage1_data,
            s_tvalid      => stage1_valid,
            s_tlast       => stage1_last,
            s_tuser       => stage1_user,
            -- Sortie
            m_tdata       => stage2_data,
            m_tvalid      => stage2_valid,
            m_tlast       => stage2_last,
            m_tuser       => stage2_user,
            -- LUT exportée
            lut_r_out     => gamma_lut_r,
            lut_g_out     => gamma_lut_g,
            lut_b_out     => gamma_lut_b,
            lut_valid     => lut_valid
        );

    -- =========================================================
    -- ÉTAGE 3 : Gray-World Balance (optionnel)
    -- =========================================================
    u_gray_world : entity work.gray_world_balance
        generic map (
            IMG_WIDTH  => IMG_WIDTH,
            IMG_HEIGHT => IMG_HEIGHT,
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk        => clk,
            rst_n      => rst_n,
            enable     => enable_balance,
            -- Entrée
            s_tdata    => stage2_data,
            s_tvalid   => stage2_valid,
            s_tlast    => stage2_last,
            s_tuser    => stage2_user,
            -- Sortie
            m_tdata    => stage3_data,
            m_tvalid   => stage3_valid,
            m_tlast    => stage3_last,
            m_tuser    => stage3_user
        );

    -- =========================================================
    -- ÉTAGE 4 : Unsharp Mask (optionnel)
    -- =========================================================
    u_unsharp : entity work.unsharp_mask
        generic map (
            IMG_WIDTH  => IMG_WIDTH,
            DATA_WIDTH => DATA_WIDTH
        )
        port map (
            clk        => clk,
            rst_n      => rst_n,
            enable     => enable_sharpen,
            -- Entrée
            s_tdata    => stage3_data,
            s_tvalid   => stage3_valid,
            s_tlast    => stage3_last,
            s_tuser    => stage3_user,
            -- Sortie
            m_tdata    => stage4_data,
            m_tvalid   => stage4_valid,
            m_tlast    => stage4_last,
            m_tuser    => stage4_user
        );

    -- =========================================================
    -- Sortie finale
    -- =========================================================
    m_axis_tdata  <= stage4_data;
    m_axis_tvalid <= stage4_valid;
    m_axis_tlast  <= stage4_last;
    m_axis_tuser  <= stage4_user;

    frame_done    <= stage4_last and stage4_valid;
    frame_dark    <= is_dark;
    frame_bright  <= is_bright;

end architecture rtl;