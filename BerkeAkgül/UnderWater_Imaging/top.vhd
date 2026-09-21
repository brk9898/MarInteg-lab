library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.ram_pkg.all; -- RAM paketinizin tanımlı olduğu varsayılıyor

entity cam_to_vga_top is
  port (
    i_Clk100     : in  std_logic;
    i_Reset      : in  std_logic;
    init         : in  std_logic; -- OV7670 init başlatma sinyali
    select_rgb   : in  std_logic; -- '0' = RGB444, '1' = YUV422 (şimdilik kullanılmıyor)
    i_GW_en      : in  std_logic; -- GW modülünü etkinleştirme sinyali

    -- OV7670 Kamera Arayüzü
    i_CAM_PCLK   : in  std_logic;
    i_CAM_VSYNC  : in  std_logic;
    i_CAM_HREF   : in  std_logic;
    i_CAM_D      : in  std_logic_vector(7 downto 0);
    o_CAM_XCLK   : out std_logic;
    
    -- Debug LED
    LED          : out std_logic_vector(15 downto 0);

    -- I2C Arayüzü (SCCB)
    scl         : inout std_logic;
    sda         : inout std_logic;

    -- VGA Çıkışları
    o_VGA_HS     : out std_logic;
    o_VGA_VS     : out std_logic;
    o_VGA_R      : out std_logic_vector(3 downto 0);
    o_VGA_G      : out std_logic_vector(3 downto 0);
    o_VGA_B      : out std_logic_vector(3 downto 0)
  );
end entity;

architecture rtl of cam_to_vga_top is

  -- Clock Sinyalleri
  signal r_div  : unsigned(1 downto 0) := (others => '0');
  signal clk25  : std_logic := '0';

  -- Writer (Kamera Yazma) Sinyalleri
  signal wr_en   : std_logic := '0';
  signal wr_x    : unsigned(9 downto 0) := (others => '0'); -- 0..639 için 10 bit
  signal wr_y    : unsigned(8 downto 0) := (others => '0'); -- 0..479 için 9 bit
  signal wr_data : std_logic_vector(11 downto 0) := (others => '0');

  signal wr_en_p   : std_logic;
  signal wr_x_p    : unsigned(9 downto 0);
  signal wr_y_p    : unsigned(8 downto 0);
  
  -- RAM Adresleme (640*480 = 307,200 piksel -> 19 bit adres gerekir)
  signal wr_addr     : std_logic_vector(18 downto 0) := (others => '0');
  signal vga_rd_addr : std_logic_vector(18 downto 0) := (others => '0');
  signal vga_rd_data : std_logic_vector(11 downto 0)  := (others => '0');

  -- Adres Hesaplama için geçici sinyaller
  signal wr_addr_int : integer range 0 to 307199 := 0;

begin

  -- 1. Clock Divider (100 MHz -> 25 MHz)
  -- OV7670 XCLK ve VGA Pixel Clock için kullanılır.
  process(i_Clk100)
  begin
    if rising_edge(i_Clk100) then
      r_div <= r_div + 1;
    end if;
  end process;
  
  clk25      <= r_div(1); -- 2. bit 25 MHz verir (100/4)
  o_CAM_XCLK <= clk25;

  -- Debug: Yazılan adresin alt bitlerini LED'de göster
  LED(7 downto 0) <= i_CAM_D(7 downto 0); 

  -- 2. OV7670 Writer Modülü
  -- Kameradan gelen veriyi alır, X ve Y koordinatlarını üretir.
  writer_inst : entity work.ov7670_to_ram_writer
    port map (
      cam_pclk  => i_CAM_PCLK,
      cam_vsync => i_CAM_VSYNC,
      cam_href  => i_CAM_HREF,
      cam_d     => i_CAM_D,
      reset_n   => not i_Reset, -- Genellikle aktif düşük reset kullanılır

      select_rgb => select_rgb, -- RGB444 modunda çalışacak (YUV422 işlenmeyecek)

      o_wr_en   => wr_en,
      o_wr_x    => wr_x,    -- 10-bit bağlı
      o_wr_y    => wr_y,    -- 9-bit bağlı
      o_wr_data => wr_data  -- Kamera Y (Luminance) verisi buraya gelmeli
    );


  -- 3. Lineer Adres Hesaplama (640x480)
  -- Formül: Address = (Y * 640) + X
  wr_addr_int <= (to_integer(wr_y) * 640) + to_integer(wr_x);
  wr_addr     <= std_logic_vector(to_unsigned(wr_addr_int, 19));

  -- 4. Dual Port RAM (Frame Buffer)
  -- Port A: Kameradan Yazma (PCLK hızında)
  -- Port B: VGA Tarafından Okuma (25 MHz hızında)
  ram_inst : entity work.xilinx_simple_dual_port_byte_write_2_clock_ram
    generic map (
      NB_COL          => 1,
      COL_WIDTH       => 12,
      RAM_DEPTH       => 307200, -- Tam 640x480 boyutu
      RAM_PERFORMANCE => "LOW_LATENCY",
      INIT_FILE       => ""
    )
    port map (
      -- Port A (Write - Camera)
      addra  => wr_addr,
      dina   => wr_data,
      clka   => i_CAM_PCLK,
      wea    => (0 => wr_en), -- std_logic_vector'e dönüşüm

      -- Port B (Read - VGA)
      addrb  => vga_rd_addr,
      clkb   => clk25,
      enb    => '1',   -- Sürekli okumaya açık
      rstb   => '0',
      regceb => '1',
      doutb  => vga_rd_data
    );

  -- 5. VGA Kontrol Modülü
  -- NOT: Grayscale görüntü için bu modülün, gelen 8-bit veriyi (vga_rd_data)
  -- R, G ve B kanallarına eşit dağıtması gerekir (Örn: R=Data[7:4], G=Data[7:4]...).
  -- Eğer modül RGB332 modundaysa görüntü renkli/karışık görünecektir.
  vga_top_inst : entity work.VGA_Final_Top_ExternRAM
    port map (
      i_Clk25   => clk25,
      i_Reset   => i_Reset,
      i_GW_en   => i_GW_en, 

      o_Rd_Addr => vga_rd_addr, -- VGA modülü okuyacağı pikselin adresini ister
      i_Rd_Data => vga_rd_data, -- RAM'den okunan veriyi alır

      o_VGA_HS  => o_VGA_HS,
      o_VGA_VS  => o_VGA_VS,
      o_VGA_R   => o_VGA_R,
      o_VGA_G   => o_VGA_G,
      o_VGA_B   => o_VGA_B
    );

  ov7670_init_top_inst : entity work.ov7670_init_top
    port map (
      clk       => i_Clk100,
      rst_n     => not i_Reset,
      start     => init,  -- Start init sequence
      busy      => open, -- Not used in this design
      init_done => open,
      scl       => scl,
      sda       => sda
    );



end architecture;