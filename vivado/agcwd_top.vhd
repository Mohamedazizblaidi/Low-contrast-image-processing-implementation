-- =============================================================
-- File: agcwd_top.vhd
-- Corrected to match all updated sub-modules
-- =============================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity agcwd_top is
    generic (
        IMG_WIDTH  : integer := 640;
        IMG_HEIGHT : integer := 480;
        ALPHA_VALUE: integer := 128
    );
    port (
        clk             : in  std_logic;
        rst_n           : in  std_logic;

        -- Input AXI4-Stream
        s_axis_tdata    : in  std_logic_vector(23 downto 0);
        s_axis_tvalid   : in  std_logic;
        s_axis_tready   : out std_logic;
        s_axis_tlast    : in  std_logic;
        s_axis_tuser    : in  std_logic;

        -- Output AXI4-Stream
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
    -- Internal pipeline signals
    -- =========================================================

    -- Stage 0 ? stats
    signal stage0_data  : std_logic_vector(23 downto 0);
    signal stage0_valid : std_logic;
    signal stage0_last  : std_logic;
    signal stage0_user  : std_logic;

    -- Stage 1 ? after bilateral
    signal stage1_data  : std_logic_vector(23 downto 0);
    signal stage1_valid : std_logic;
    signal stage1_last  : std_logic;
    signal stage1_user  : std_logic;

    -- Stage 2 ? after gamma LUT
    signal stage2_data  : std_logic_vector(23 downto 0);
    signal stage2_valid : std_logic;
    signal stage2_last  : std_logic;
    signal stage2_user  : std_logic;

    -- Stage 3 ? after gray world
    signal stage3_data  : std_logic_vector(23 downto 0);
    signal stage3_valid : std_logic;
    signal stage3_last  : std_logic;
    signal stage3_user  : std_logic;

    -- Stage 4 ? after unsharp
    signal stage4_data  : std_logic_vector(23 downto 0);
    signal stage4_valid : std_logic;
    signal stage4_last  : std_logic;
    signal stage4_user  : std_logic;

    -- =========================================================
    -- Statistics outputs
    -- =========================================================
    signal frame_mean   : unsigned(7 downto 0);
    signal frame_std    : unsigned(7 downto 0);
    signal is_dark      : std_logic;
    signal is_bright    : std_logic;
    signal stats_done   : std_logic;

    -- =========================================================
    -- LUT export (flattened std_logic_vector 256x8=2048 bits)
    -- =========================================================
    signal gamma_lut_r  : std_logic_vector(2047 downto 0);
    signal gamma_lut_g  : std_logic_vector(2047 downto 0);
    signal gamma_lut_b  : std_logic_vector(2047 downto 0);
    signal lut_valid    : std_logic;

begin

    -- Always ready to receive
    s_axis_tready <= '1';

    -- Connect input to stage0
    stage0_data  <= s_axis_tdata;
    stage0_valid <= s_axis_tvalid;
    stage0_last  <= s_axis_tlast;
    stage0_user  <= s_axis_tuser;

    -- =========================================================
    -- Channel Statistics
    -- =========================================================
    u_stats : entity work.channel_stats
        generic map (
            IMG_WIDTH  => IMG_WIDTH,
            IMG_HEIGHT => IMG_HEIGHT,
            DATA_WIDTH => 8
        )
        port map (
            clk         => clk,
            rst_n       => rst_n,
            pixel_in    => stage0_data,
            pix_valid   => stage0_valid,
            frame_start => stage0_user,
            frame_end   => stage0_last,
            mean_out    => frame_mean,
            std_out     => frame_std,
            is_dark     => is_dark,
            is_bright   => is_bright,
            stats_done  => stats_done
        );

    -- =========================================================
    -- Bilateral Filter
    -- =========================================================
    u_bilateral : entity work.bilateral_filter
        generic map (
            IMG_WIDTH   => IMG_WIDTH,
            DATA_WIDTH  => 8,
            KERNEL_SIZE => 5
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            enable    => enable_denoise,
            s_tdata   => stage0_data,
            s_tvalid  => stage0_valid,
            s_tlast   => stage0_last,
            s_tuser   => stage0_user,
            m_tdata   => stage1_data,
            m_tvalid  => stage1_valid,
            m_tlast   => stage1_last,
            m_tuser   => stage1_user
        );

    -- =========================================================
    -- Gamma LUT Engine (AGCWD core)
    -- =========================================================
    u_gamma : entity work.gamma_lut_engine
        generic map (
            IMG_WIDTH  => IMG_WIDTH,
            IMG_HEIGHT => IMG_HEIGHT
        )
        port map (
            clk        => clk,
            rst_n      => rst_n,
            frame_mean => frame_mean,
            is_dark    => is_dark,
            is_bright  => is_bright,
            s_tdata    => stage1_data,
            s_tvalid   => stage1_valid,
            s_tlast    => stage1_last,
            s_tuser    => stage1_user,
            m_tdata    => stage2_data,
            m_tvalid   => stage2_valid,
            m_tlast    => stage2_last,
            m_tuser    => stage2_user,
            lut_r_out  => gamma_lut_r,
            lut_g_out  => gamma_lut_g,
            lut_b_out  => gamma_lut_b,
            lut_valid  => lut_valid
        );

    -- =========================================================
    -- Gray World Balance
    -- =========================================================
    u_gray_world : entity work.gray_world_balance
        generic map (
            IMG_WIDTH  => IMG_WIDTH,
            IMG_HEIGHT => IMG_HEIGHT,
            DATA_WIDTH => 8
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            enable    => enable_balance,
            s_tdata   => stage2_data,
            s_tvalid  => stage2_valid,
            s_tlast   => stage2_last,
            s_tuser   => stage2_user,
            m_tdata   => stage3_data,
            m_tvalid  => stage3_valid,
            m_tlast   => stage3_last,
            m_tuser   => stage3_user
        );

    -- =========================================================
    -- Unsharp Mask
    -- =========================================================
    u_unsharp : entity work.unsharp_mask
        generic map (
            IMG_WIDTH  => IMG_WIDTH,
            DATA_WIDTH => 8
        )
        port map (
            clk       => clk,
            rst_n     => rst_n,
            enable    => enable_sharpen,
            s_tdata   => stage3_data,
            s_tvalid  => stage3_valid,
            s_tlast   => stage3_last,
            s_tuser   => stage3_user,
            m_tdata   => stage4_data,
            m_tvalid  => stage4_valid,
            m_tlast   => stage4_last,
            m_tuser   => stage4_user
        );

    -- =========================================================
    -- Final output
    -- =========================================================
    m_axis_tdata  <= stage4_data;
    m_axis_tvalid <= stage4_valid;
    m_axis_tlast  <= stage4_last;
    m_axis_tuser  <= stage4_user;

    frame_done    <= stage4_last and stage4_valid;
    frame_dark    <= is_dark;
    frame_bright  <= is_bright;

end architecture rtl;