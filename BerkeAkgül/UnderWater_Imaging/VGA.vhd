library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity VGA_Final_Top_ExternRAM is
  Port (
    i_Clk25    : in  std_logic; -- Top modülden gelen 25 MHz
    i_Reset    : in  std_logic;
    i_GW_en    : in  std_logic; -- GW modülünü etkinleştirmek için (kullanılmayabilir)

    -- External RAM okuma portu (Artık 640x480 = 307,200 adres)
    o_Rd_Addr  : out std_logic_vector(18 downto 0); -- 19 bit yapıldı
    i_Rd_Data  : in  std_logic_vector(11 downto 0);

    -- VGA Çıkışları
    o_VGA_HS   : out std_logic;
    o_VGA_VS   : out std_logic;
    o_VGA_R    : out std_logic_vector(3 downto 0);
    o_VGA_G    : out std_logic_vector(3 downto 0);
    o_VGA_B    : out std_logic_vector(3 downto 0)
  );
end VGA_Final_Top_ExternRAM;

architecture Behavioral of VGA_Final_Top_ExternRAM is

  -- VGA Sürücü Sinyalleri
  signal w_Pixel_X, w_Pixel_Y : integer := 0;
  signal w_Video_On           : std_logic := '0';

  -- Tam Ekran Ayarları (640x480)
  constant IMG_W   : integer := 640;
  constant IMG_H   : integer := 480;
  -- Başlangıç noktaları artık 0, çünkü tüm ekranı kullanıyoruz
  constant START_X : integer := 0; 
  constant START_Y : integer := 0; 

  signal Y1 : signed(5 downto 0) := (others => '0');
  signal U  : signed(5 downto 0) := (others => '0');
  signal V  : signed(5 downto 0) := (others => '0');
  signal Y2 : signed(5 downto 0) := (others => '0');

  signal red   : signed(6 downto 0);
  signal green : signed(6 downto 0);
  signal blue  : signed(6 downto 0);

  signal R_out, G_out, B_out : std_logic_vector(7 downto 0); -- GW modülünden çıkan renkler

  -- Video Aktif Sinyalleri ve Gecikme Hattı
  signal w_Pixel_Valid   : std_logic := '0';
  signal w_Pixel_Valid_d : std_logic := '0'; -- RAM okuma gecikmesi (Latency) için

  signal frame_done : std_logic := '0'; -- Dummy sinyal, gerçek kamera verisi yok

  -- Adres sayacı (19 bit)
  signal rd_addr_u : unsigned(18 downto 0) := (others=>'0');

  function clamp8(x : signed(6 downto 0)) return std_logic_vector is
    variable result : std_logic_vector(3 downto 0);
  begin
    if x > 63 then
      result := "1111";
    elsif x < 0 then
      result := "0000";
    else
      result := std_logic_vector(x(5 downto 2)); -- Orantılı olarak 6 bitlik değeri 4 bite indir
    end if;
    return result;
  end function;

begin

  -- VGA Zamanlama Modülü
  -- (Bu modülün standart 640x480 @ 60Hz ürettiği varsayılır)
  inst_VGA: entity work.VGA_Driver_Mod
    port map (
      clk_25mhz => i_Clk25,
      h_sync    => o_VGA_HS,
      v_sync    => o_VGA_VS,
      video_on  => w_Video_On,
      pixel_x   => w_Pixel_X, -- 0..639
      pixel_y   => w_Pixel_Y  -- 0..479
    );

  -- Piksel Geçerlilik Kontrolü
  -- Video_On aktifse ve sınırlar içindeysek (ki full ekran olduğu için Video_On yeterli)
  w_Pixel_Valid <= '1' when (w_Video_On = '1' and 
                             w_Pixel_X >= START_X and w_Pixel_X < START_X + IMG_W and
                             w_Pixel_Y >= START_Y and w_Pixel_Y < START_Y + IMG_H)
                     else '0';

  frame_done <= '1' when w_Pixel_Y = IMG_H and w_Pixel_X = IMG_W else '0';                   

  -- Adres Hesaplama (Registered) + Valid Gecikmesi
  process(i_Clk25)
    -- Çarpma işlemi büyük olacağı için değişken integer kullanıyoruz
    variable addr_int : integer range 0 to 307200;
  begin
    if rising_edge(i_Clk25) then
      if i_Reset = '1' then
        rd_addr_u       <= (others=>'0');
        w_Pixel_Valid_d <= '0';
      else
        
        if w_Pixel_Valid = '1' then
          -- Lineer Adres Formülü: (Y * 640) + X
          -- Top modüldeki yazma mantığıyla birebir aynı olmalı.
          addr_int := (w_Pixel_Y * IMG_W) + w_Pixel_X;
          
          rd_addr_u <= to_unsigned(addr_int, 19);
        else
          rd_addr_u <= (others=>'0');
        end if;

        -- Block RAM okuması 1 saat çevrimi sürdüğü için valid sinyalini de geciktiriyoruz
        w_Pixel_Valid_d <= w_Pixel_Valid;
        
      end if;
    end if;
  end process;

  -- Adresi dışarı ver
  o_Rd_Addr <= std_logic_vector(rd_addr_u);

-- VGA_Final_Top_ExternRAM içindeki renk atama bloğu:
  process(i_Clk25)
  begin
    if rising_edge(i_Clk25) then
      if w_Pixel_Valid_d = '1' then

        if rd_addr_u(0) = '0' then
          Y1    <= signed(i_Rd_Data(11 downto 6)); -- Tüm baytı al
          U     <= signed(i_Rd_Data(5 downto 0)); -- Tüm baytı al
        elsif rd_addr_u(0) = '1' then
          Y2    <= signed(i_Rd_Data(11 downto 6)); -- Tüm baytı al
          V     <= signed(i_Rd_Data(5 downto 0)); -- Tüm baytı al

        else
        end if;

        -- Basit YUV->RGB dönüşümü (kaba katsayılarla)
        if rd_addr_u(0) = '0' then -- Y1 geldiğinde RGB hesapla
          red   <= ("0" & Y1) + ("0" & U - 32); 
          green <= ("0" & Y1); 
          blue  <= ("0" & Y1) + ("0" & V - 32); 
        elsif rd_addr_u(0) = '1' then -- Y2 geldiğinde RGB hesapla
          red   <= ("0" & Y2) + ("0" & U - 32); 
          green <= ("0" & Y2); 
          blue  <= ("0" & Y2) + ("0" & V - 32); 
        end if;

        if(i_GW_en = '1') then
          -- GW modülünden çıkan renkleri kullan
          o_VGA_R <= clamp8(signed('0' & R_out(7 downto 2))); -- GW'den gelen 8 bitlik rengi 4 bite indir
          o_VGA_G <= clamp8(signed('0' & G_out(7 downto 2))); -- GW'den gelen 8 bitlik rengi 4 bite indir
          o_VGA_B <= clamp8(signed('0' & B_out(7 downto 2))); -- GW'den gelen 8 bitlik rengi 4 bite indir
        else
          -- Normal RGB değerlerini kullan
          o_VGA_R <= clamp8(red);
          o_VGA_G <= clamp8(green);
          o_VGA_B <= clamp8(blue);
        end if;
        


      else
        o_VGA_R <= (others => '0');
        o_VGA_G <= (others => '0');
        o_VGA_B <= (others => '0');
      end if;
    end if;
  end process;

  GW: entity work.GW_Top 
    port map (
      clk => i_Clk25,
      reset => i_Reset,
      R_i => clamp8(red) & "0000", -- Dummy input, gerçek kamera verisi yok
      G_i => clamp8(green) & "0000", -- Dummy input, gerçek kamera verisi yok
      B_i => clamp8(blue) & "0000", -- Dummy input, gerçek kamera verisi yok
      pixel_valid => w_Pixel_Valid_d,     -- Dummy input, gerçek kamera verisi yok
      frame_done => frame_done,      -- Dummy input, gerçek kamera verisi yok
      R_out => R_out,
      G_out => G_out,
      B_out => B_out
    );

end Behavioral;