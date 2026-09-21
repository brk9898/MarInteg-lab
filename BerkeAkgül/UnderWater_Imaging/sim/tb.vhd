library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_cam_to_vga is
end entity;

architecture tb of tb_cam_to_vga is

  ------------------------------------------------------------------
  -- Clocks / reset
  ------------------------------------------------------------------
  signal clk100   : std_logic := '0';
  signal reset    : std_logic := '1';

  ------------------------------------------------------------------
  -- OV7670 signals
  ------------------------------------------------------------------
  signal cam_pclk   : std_logic;
  signal cam_vsync  : std_logic;
  signal cam_href   : std_logic;
  signal cam_d      : std_logic_vector(7 downto 0);

  ------------------------------------------------------------------
  -- VGA outputs (just observe in sim)
  ------------------------------------------------------------------
  signal vga_hs : std_logic;
  signal vga_vs : std_logic;
  signal vga_r  : std_logic_vector(3 downto 0);
  signal vga_g  : std_logic_vector(3 downto 0);
  signal vga_b  : std_logic_vector(3 downto 0);

begin

  ------------------------------------------------------------------
  -- 100 MHz system clock
  ------------------------------------------------------------------
  clk100 <= not clk100 after 5 ns;  -- 100 MHz

  ------------------------------------------------------------------
  -- Reset
  ------------------------------------------------------------------
  process
  begin
    reset <= '1';
    wait for 200 ns;
    reset <= '0';
    wait;
  end process;

  ------------------------------------------------------------------
  -- OV7670 MODEL
  ------------------------------------------------------------------
  cam_model : entity work.ov7670_model
    generic map (
      G_PCLK_PERIOD => 40 ns,   -- 25 MHz PCLK
      G_TESTPATTERN => true
    )
    port map (
      reset_n   => not reset,
      enable    => '1',

      pclk      => cam_pclk,
      vsync     => cam_vsync,
      href      => cam_href,
      d         => cam_d,

      reg_wr_en => '0',
      reg_addr  => (others => '0'),
      reg_wdata => (others => '0')
    );

  ------------------------------------------------------------------
  -- DUT : Camera -> RAM -> VGA
  ------------------------------------------------------------------
  dut : entity work.cam_to_vga_top
    port map (
      i_Clk100     => clk100,
      i_Reset      => reset,
      init => '1',  -- OV7670 model'ün reset'i ile senkronize   
      select_rgb => '0',  -- RGB444 modunda test

      i_CAM_PCLK   => cam_pclk,
      i_CAM_VSYNC  => cam_vsync,
      i_CAM_HREF   => cam_href,
      i_CAM_D      => cam_d,
      i_gw_en      => '0',


      o_VGA_HS     => vga_hs,
      o_VGA_VS     => vga_vs,
      o_VGA_R      => vga_r,
      o_VGA_G      => vga_g,
      o_VGA_B      => vga_b
    );

  ------------------------------------------------------------------
  -- Simulation end (optional)
  ------------------------------------------------------------------
  process
  begin
    wait for 40 ms;  -- ~1 VGA frame @ 60 Hz
    report "Simulation finished." severity note;
    wait;
  end process;

end architecture;
